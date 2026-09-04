import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart'
    show CrmAsyncView, CrmCardList, CrmField, CrmMetaLine, CrmSheet, showCrmSheet;
import 'hr_providers.dart';
import 'payroll_catalog_screens.dart' show PayrollAssignSheet;

/// Payroll settings: the PAYE bracket table and the three blanket
/// exemptions. One tab, because all four are tenant-wide policy rather than
/// per-employee records like the catalogs.
class PayrollSettingsTab extends ConsumerStatefulWidget {
  const PayrollSettingsTab({super.key, required this.canManage});

  final bool canManage;

  @override
  ConsumerState<PayrollSettingsTab> createState() =>
      _PayrollSettingsTabState();
}

class _PayrollSettingsTabState extends ConsumerState<PayrollSettingsTab> {
  /// A local, editable copy of the bracket table. `PUT /payroll-settings`
  /// replaces the whole array, so brackets are added, edited and removed
  /// here and only sent to the server on "Save changes".
  List<PayeBracket>? _brackets;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  void _seed(PayrollSettings settings) {
    _brackets ??= [for (final b in settings.payeBrackets) b];
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(payrollSettingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CrmAsyncView(
      value: settings,
      errorTitle: 'Could not load payroll settings',
      onRetry: () => ref.invalidate(payrollSettingsProvider),
      builder: (data) {
        _seed(data);
        final brackets = _brackets!;

        return RefreshIndicator(
          onRefresh: () async {
            _brackets = null;
            _dirty = false;
            ref.invalidate(payrollSettingsProvider);
            await ref.read(payrollSettingsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              SectionHeader(
                'PAYE brackets',
                trailing: widget.canManage
                    ? TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add bracket'),
                        onPressed: _addBracket,
                      )
                    : null,
              ),
              const SizedBox(height: Spacing.sm),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: Spacing.sm),
              ],
              if (brackets.isEmpty)
                const Card(
                  child: StateMessage(
                    icon: Icons.percent_outlined,
                    title: 'No brackets yet',
                    message: 'Add at least one bracket to compute PAYE.',
                  ),
                )
              else
                CrmCardList(
                  children: [
                    for (final (i, b) in brackets.indexed)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${Formatting.currency(b.min)} – '
                          '${b.max == null ? 'no limit' : Formatting.currency(b.max)}',
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: CrmMetaLine(
                            '${Formatting.amount(b.rate)}% · base '
                            '${Formatting.currency(b.baseDeduction)}',
                          ),
                        ),
                        trailing: widget.canManage
                            ? const Icon(Icons.chevron_right)
                            : null,
                        onTap: widget.canManage
                            ? () => _editBracket(i)
                            : null,
                      ),
                  ],
                ),
              if (widget.canManage) ...[
                const SizedBox(height: Spacing.md),
                PrimaryButton(
                  label: _saving ? 'Saving…' : 'Save changes',
                  busy: _saving,
                  onPressed: (!_dirty || _saving) ? null : _saveBrackets,
                ),
                if (_dirty) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Unsaved changes — tap Save changes to apply them.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Exemptions'),
              const SizedBox(height: Spacing.sm),
              CrmCardList(
                children: [
                  ListTile(
                    title: const Text('PAYE exemptions'),
                    subtitle: const Text(
                      'Employees not subject to PAYE at all.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openExemption(
                      title: 'PAYE exemptions',
                      fetch: () =>
                          ref.read(hrServiceProvider).payeExemptions(),
                      onSave:
                          ({
                            required userId,
                            required isActive,
                            String? fieldText,
                          }) => ref
                              .read(hrServiceProvider)
                              .setPayeExemption(
                                userId: userId,
                                isActive: isActive,
                              ),
                    ),
                  ),
                  ListTile(
                    title: const Text('Attendance penalty exemptions'),
                    subtitle: const Text(
                      'Employees exempt from attendance penalties.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openExemption(
                      title: 'Attendance penalty exemptions',
                      fetch: () => ref
                          .read(hrServiceProvider)
                          .attendancePenaltyExemptions(),
                      onSave:
                          ({
                            required userId,
                            required isActive,
                            String? fieldText,
                          }) => ref
                              .read(hrServiceProvider)
                              .setAttendancePenaltyExemption(
                                userId: userId,
                                isActive: isActive,
                              ),
                    ),
                  ),
                  ListTile(
                    title: const Text('Late report penalty exemptions'),
                    subtitle: const Text(
                      'Employees exempt from late-report penalties.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openExemption(
                      title: 'Late report penalty exemptions',
                      fetch: () => ref
                          .read(hrServiceProvider)
                          .reportPenaltyExemptions(),
                      onSave:
                          ({
                            required userId,
                            required isActive,
                            String? fieldText,
                          }) => ref
                              .read(hrServiceProvider)
                              .setReportPenaltyExemption(
                                userId: userId,
                                isActive: isActive,
                              ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addBracket() => showCrmSheet<void>(
    context: context,
    builder: (_) => PayeBracketEditSheet(
      onSave: (b) => setState(() {
        _brackets = [...?_brackets, b];
        _dirty = true;
      }),
    ),
  );

  Future<void> _editBracket(int index) => showCrmSheet<void>(
    context: context,
    builder: (_) => PayeBracketEditSheet(
      existing: _brackets![index],
      onSave: (b) => setState(() {
        _brackets![index] = b;
        _dirty = true;
      }),
      onRemove: _brackets!.length > 1
          ? () => setState(() {
              _brackets!.removeAt(index);
              _dirty = true;
            })
          : null,
    ),
  );

  Future<void> _saveBrackets() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(hrServiceProvider)
          .updatePayrollSettings(_brackets!);
      if (mounted) {
        setState(() {
          _brackets = [for (final b in updated.payeBrackets) b];
          _dirty = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Payroll settings saved.')));
      }
      ref.invalidate(payrollSettingsProvider);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openExemption({
    required String title,
    required Future<SubscriptionsPage> Function() fetch,
    required Future<void> Function({
      required String userId,
      required bool isActive,
      String? fieldText,
    })
    onSave,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (_) => PayrollAssignSheet(
      eyebrow: 'Payroll settings',
      title: title,
      readOnly: !widget.canManage,
      fetch: fetch,
      onSave: onSave,
    ),
  );
}

/// Add, edit or remove one PAYE bracket. Mutations happen through the two
/// callbacks straight into the caller's local list — this sheet never talks
/// to the server; that only happens when the whole table is saved.
class PayeBracketEditSheet extends StatefulWidget {
  const PayeBracketEditSheet({
    super.key,
    this.existing,
    required this.onSave,
    this.onRemove,
  });

  final PayeBracket? existing;
  final ValueChanged<PayeBracket> onSave;

  /// Null when there is only one bracket left, or when adding a new one —
  /// the table always needs at least one row.
  final VoidCallback? onRemove;

  @override
  State<PayeBracketEditSheet> createState() => _PayeBracketEditSheetState();
}

class _PayeBracketEditSheetState extends State<PayeBracketEditSheet> {
  late final _min = TextEditingController(
    text: widget.existing == null ? '' : Formatting.amount(widget.existing!.min),
  );
  late final _max = TextEditingController(
    text: widget.existing?.max == null
        ? ''
        : Formatting.amount(widget.existing!.max),
  );
  late final _rate = TextEditingController(
    text: widget.existing == null
        ? ''
        : Formatting.amount(widget.existing!.rate),
  );
  late final _baseDeduction = TextEditingController(
    text: widget.existing == null
        ? ''
        : Formatting.amount(widget.existing!.baseDeduction),
  );
  late bool _noUpperLimit =
      widget.existing != null && widget.existing!.max == null;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    _rate.dispose();
    _baseDeduction.dispose();
    super.dispose();
  }

  void _save() {
    final min = double.tryParse(_min.text.replaceAll(',', '').trim());
    final rate = double.tryParse(_rate.text.replaceAll(',', '').trim());
    final base = double.tryParse(
      _baseDeduction.text.replaceAll(',', '').trim(),
    );
    final max = _noUpperLimit
        ? null
        : double.tryParse(_max.text.replaceAll(',', '').trim());
    if (min == null ||
        rate == null ||
        base == null ||
        (!_noUpperLimit && max == null)) {
      setState(
        () => _error = 'Fill in every field, or turn on "No upper limit".',
      );
      return;
    }
    if (!_noUpperLimit && max! <= min) {
      setState(
        () => _error = 'The upper limit must be greater than the lower one.',
      );
      return;
    }
    widget.onSave(PayeBracket(min: min, max: max, rate: rate, baseDeduction: base));
    Navigator.of(context).pop();
  }

  void _remove() {
    widget.onRemove?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CrmSheet(
      eyebrow: 'PAYE bracket',
      title: _editing ? 'Edit bracket' : 'New bracket',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Row(
          children: [
            Expanded(
              child: CrmField(
                label: 'From',
                child: TextField(
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: '0.00'),
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: CrmField(
                label: 'Up to',
                child: TextField(
                  controller: _max,
                  enabled: !_noUpperLimit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: _noUpperLimit ? 'No limit' : '0.00',
                  ),
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('No upper limit'),
          subtitle: const Text('The top bracket only'),
          value: _noUpperLimit,
          onChanged: (v) => setState(() => _noUpperLimit = v),
        ),
        const SizedBox(height: Spacing.sm),
        Row(
          children: [
            Expanded(
              child: CrmField(
                label: 'Rate',
                child: TextField(
                  controller: _rate,
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
                label: 'Base deduction',
                child: TextField(
                  controller: _baseDeduction,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: '0.00'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _editing ? 'Save bracket' : 'Add bracket',
          onPressed: _save,
        ),
        if (widget.onRemove != null) ...[
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: _remove,
            child: Text(
              'Remove bracket',
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

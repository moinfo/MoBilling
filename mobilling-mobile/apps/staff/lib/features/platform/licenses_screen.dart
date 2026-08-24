import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart'
    show
        CrmCardList,
        CrmDetailRow,
        CrmField,
        CrmPickerField,
        CrmSheet,
        CrmStatusLine,
        showCrmMessage,
        showCrmSheet;
import 'license_plans_screen.dart' show licensePlansProvider;
import 'platform_providers.dart' show platformServiceProvider;
import 'platform_shell.dart' show PlatformListScaffold;

/// Self-hosted install licenses (WHMCS-style) — each key locks to the domain
/// that first checks in with it.
///
/// A plain list rather than an infinite scroll: self-hosted licensing is a
/// rare workflow, and the web's own table never expects more than a couple of
/// pages, so one generous page (see `PlatformService.licenses`) covers it.
final AutoDisposeFutureProvider<List<License>> licensesProvider =
    FutureProvider.autoDispose<List<License>>(
      (ref) => ref.watch(platformServiceProvider).licenses(),
    );

/// Months to add for a preview of `License::calculateExpiry` — client-side
/// only, matching the web's `previewExpiry`. The server is the source of
/// truth for the actual value stored.
String previewLicenseExpiry(DateTime startsAt, String billingPeriod) {
  if (billingPeriod == LicenseBillingPeriods.perpetual) return 'No expiry';
  final months = LicenseBillingPeriods.months(billingPeriod);
  if (months == null) return '—';
  return Formatting.date(_addMonths(startsAt, months));
}

DateTime _addMonths(DateTime date, int months) {
  final total = date.month - 1 + months;
  final year = date.year + total ~/ 12;
  final month = total % 12 + 1;
  return DateTime(year, month, date.day);
}

LicensePlan? _planFor(List<LicensePlan> plans, String product) {
  for (final plan in plans) {
    if (plan.product == product) return plan;
  }
  return null;
}

class LicensesScreen extends ConsumerWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformListScaffold<License>(
      title: 'Licenses',
      value: ref.watch(licensesProvider),
      onRetry: () => ref.invalidate(licensesProvider),
      emptyIcon: Icons.vpn_key_outlined,
      emptyTitle: 'No licenses issued yet',
      footnote: 'Each key locks to the domain that first checks in with it.',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'issue-license',
        onPressed: () => _issue(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Issue license'),
      ),
      itemBuilder: (context, license) => _LicenseRow(license: license),
    );
  }

  Future<void> _issue(BuildContext context, WidgetRef ref) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _LicenseFormSheet(),
    );
    if (saved == true) ref.invalidate(licensesProvider);
  }
}

class _LicenseRow extends ConsumerWidget {
  const _LicenseRow({required this.license});

  final License license;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      LicensePackages.label(license.product),
      license.domain ?? 'not activated',
      license.billingPeriod == LicenseBillingPeriods.perpetual
          ? 'perpetual'
          : 'expires ${Formatting.date(license.expiresAt)}',
    ].join(' · ');

    return ListTile(
      title: Text(
        license.customerName,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: CrmStatusLine(status: license.status, meta: meta),
      ),
      trailing: Icon(Icons.chevron_right, size: 20, color: scheme.outline),
      onTap: () => _open(context, ref),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final choice = await showCrmSheet<String>(
      context: context,
      builder: (_) => _LicenseDetailSheet(license: license),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: license.licenseKey));
        if (context.mounted) showCrmMessage(context, 'License key copied.');
      case 'edit':
        final saved = await showCrmSheet<bool>(
          context: context,
          builder: (_) => _LicenseFormSheet(existing: license),
        );
        if (saved == true) ref.invalidate(licensesProvider);
      case 'renew':
        final saved = await showCrmSheet<bool>(
          context: context,
          builder: (_) => _RenewSheet(existing: license),
        );
        if (saved == true) ref.invalidate(licensesProvider);
      case 'unbind':
        await _unbind(context, ref);
      case 'delete':
        await _delete(context, ref);
    }
  }

  Future<void> _unbind(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Unbind ${license.domain}?',
          style: Type.display(22, color: scheme.onSurface),
        ),
        content: const Text(
          'This license can then activate on a different install. The '
          'current activation history is cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unbind domain'),
          ),
        ],
      ),
    );
    if (sure != true) return;

    try {
      await ref.read(platformServiceProvider).unbindLicenseDomain(license.id);
      ref.invalidate(licensesProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Domain cleared — license can now activate on a new install.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete this license?',
          style: Type.display(22, color: scheme.onSurface),
        ),
        content: Text(
          'The license for ${license.customerName} will stop validating '
          'immediately. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
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
      final message = await ref
          .read(platformServiceProvider)
          .deleteLicense(license.id);
      ref.invalidate(licensesProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'License deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _LicenseDetailSheet extends StatelessWidget {
  const _LicenseDetailSheet({required this.license});

  final License license;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CrmSheet(
      eyebrow: LicensePackages.label(license.product),
      title: license.customerName,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CrmDetailRow('License key', license.licenseKey),
                CrmDetailRow('Email', license.customerEmail),
                CrmDetailRow('Domain', license.domain ?? 'Not activated yet'),
                CrmDetailRow(
                  'Billing',
                  LicenseBillingPeriods.label(license.billingPeriod),
                ),
                if (license.amountPaid != null)
                  CrmDetailRow(
                    'Amount paid',
                    Formatting.currency(license.amountPaid!),
                  ),
                CrmDetailRow(
                  'Expires',
                  license.billingPeriod == LicenseBillingPeriods.perpetual
                      ? 'Perpetual'
                      : Formatting.date(license.expiresAt),
                ),
                CrmDetailRow(
                  'Last check-in',
                  license.lastValidatedAt == null
                      ? 'Never'
                      : Formatting.dateTime(license.lastValidatedAt),
                ),
                CrmDetailRow(
                  'Activations',
                  Formatting.integer(license.activationsCount),
                ),
                if (license.notes != null && license.notes!.isNotEmpty)
                  CrmDetailRow('Notes', license.notes!),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        CrmCardList(
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined, size: 20),
              title: const Text('Copy license key'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh_outlined, size: 20),
              title: const Text('Renew'),
              subtitle: const Text('Extend the expiry date'),
              onTap: () => Navigator.pop(context, 'renew'),
            ),
            if (license.domain != null)
              ListTile(
                leading: const Icon(Icons.lock_open_outlined, size: 20),
                title: const Text('Unbind domain'),
                subtitle: const Text('Move to a new install'),
                onTap: () => Navigator.pop(context, 'unbind'),
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                size: 20,
                color: scheme.error,
              ),
              title: Text(
                'Delete license',
                style: TextStyle(color: scheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LicenseFormSheet extends ConsumerStatefulWidget {
  const _LicenseFormSheet({this.existing});

  final License? existing;

  @override
  ConsumerState<_LicenseFormSheet> createState() => _LicenseFormSheetState();
}

class _LicenseFormSheetState extends ConsumerState<_LicenseFormSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  late String _product;
  late DateTime _startsAt;
  late String _billingPeriod;
  late String _status;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name.text = existing?.customerName ?? '';
    _email.text = existing?.customerEmail ?? '';
    _amount.text = existing?.amountPaid == null
        ? ''
        : existing!.amountPaid!.toStringAsFixed(2);
    _notes.text = existing?.notes ?? '';
    _product = existing?.product ?? LicensePackages.general;
    _startsAt = existing?.startsAt ?? DateTime.now();
    _billingPeriod = existing?.billingPeriod ?? LicenseBillingPeriods.annual;
    _status = existing?.status ?? 'active';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _startsAt = picked);
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the customer name.');
      return;
    }
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final amount = _amount.text.trim().isEmpty
        ? null
        : double.tryParse(_amount.text.trim());
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    try {
      final service = ref.read(platformServiceProvider);
      String message;
      if (_isEdit) {
        await service.updateLicense(
          widget.existing!.id,
          customerName: _name.text.trim(),
          customerEmail: _email.text.trim(),
          status: _status,
          notes: notes,
        );
        message = 'License updated.';
      } else {
        final created = await service.createLicense(
          customerName: _name.text.trim(),
          customerEmail: _email.text.trim(),
          product: _product,
          startsAt: _startsAt,
          billingPeriod: _billingPeriod,
          amountPaid: amount,
          notes: notes,
        );
        message = 'License issued — key ${created.licenseKey}';
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, message);
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
    final plans = ref.watch(licensePlansProvider);
    final catalogPrice = plans.maybeWhen(
      data: (list) => _planFor(list, _product)?.priceFor(_billingPeriod),
      orElse: () => null,
    );

    return CrmSheet(
      eyebrow: _isEdit ? widget.existing!.licenseKey : null,
      title: _isEdit ? 'Edit license' : 'Issue license',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Customer name',
          child: TextField(
            controller: _name,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.words,
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Customer email',
          child: TextField(
            controller: _email,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
          ),
        ),
        if (!_isEdit) ...[
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Package',
            child: DropdownButtonFormField<String>(
              initialValue: _product,
              items: [
                for (final p in LicensePackages.values)
                  DropdownMenuItem(
                    value: p,
                    child: Text(LicensePackages.label(p)),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _product = v!),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmPickerField(
            label: 'Start date',
            value: Formatting.date(_startsAt),
            onTap: _submitting ? null : _pickStart,
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Billing period',
            child: DropdownButtonFormField<String>(
              initialValue: _billingPeriod,
              items: [
                for (final p in LicenseBillingPeriods.values)
                  DropdownMenuItem(
                    value: p,
                    child: Text(LicenseBillingPeriods.label(p)),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _billingPeriod = v!),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Expires: ${previewLicenseExpiry(_startsAt, _billingPeriod)}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Amount paid',
            child: TextField(
              controller: _amount,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                prefixText: '${Formatting.tenantCurrency} ',
                hintText: catalogPrice == null
                    ? 'No list price set — enter manually'
                    : 'List price: ${Formatting.currency(catalogPrice)}',
              ),
            ),
          ),
        ],
        if (_isEdit) ...[
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Status',
            child: DropdownButtonFormField<String>(
              initialValue: _status,
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                DropdownMenuItem(value: 'expired', child: Text('Expired')),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _status = v!),
            ),
          ),
        ],
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes',
          child: TextField(
            controller: _notes,
            enabled: !_submitting,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        if (_isEdit) ...[
          const SizedBox(height: Spacing.sm),
          Text(
            'Use Renew to extend the expiry date.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : (_isEdit ? 'Save' : 'Issue license'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

class _RenewSheet extends ConsumerStatefulWidget {
  const _RenewSheet({required this.existing});

  final License existing;

  @override
  ConsumerState<_RenewSheet> createState() => _RenewSheetState();
}

class _RenewSheetState extends ConsumerState<_RenewSheet> {
  final _amount = TextEditingController();
  late String _billingPeriod;
  late DateTime _startsAt;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _billingPeriod = existing.billingPeriod == LicenseBillingPeriods.perpetual
        ? LicenseBillingPeriods.annual
        : existing.billingPeriod;
    // Renewing before expiry extends from where the current period ends, not
    // from today — otherwise the customer loses time they already paid for.
    final expires = existing.expiresAt;
    _startsAt = (expires != null && expires.isAfter(DateTime.now()))
        ? expires
        : DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _startsAt = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final amount = _amount.text.trim().isEmpty
        ? null
        : double.tryParse(_amount.text.trim());
    final existing = widget.existing;

    try {
      await ref
          .read(platformServiceProvider)
          .updateLicense(
            existing.id,
            customerName: existing.customerName,
            customerEmail: existing.customerEmail,
            // Renewing an expired license reactivates it.
            status: existing.status == 'expired' ? 'active' : existing.status,
            startsAt: _startsAt,
            billingPeriod: _billingPeriod,
            amountPaid: amount,
            notes: existing.notes,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'License renewed.');
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
    final plans = ref.watch(licensePlansProvider);
    final catalogPrice = plans.maybeWhen(
      data: (list) =>
          _planFor(list, widget.existing.product)?.priceFor(_billingPeriod),
      orElse: () => null,
    );

    return CrmSheet(
      eyebrow: widget.existing.customerName,
      title: 'Renew license',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Text(
          'Current expiry: '
          '${widget.existing.billingPeriod == LicenseBillingPeriods.perpetual ? 'Perpetual' : Formatting.date(widget.existing.expiresAt)}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Billing period',
          child: DropdownButtonFormField<String>(
            initialValue: _billingPeriod,
            items: [
              for (final p in LicenseBillingPeriods.values)
                DropdownMenuItem(
                  value: p,
                  child: Text(LicenseBillingPeriods.label(p)),
                ),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _billingPeriod = v!),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Extend from',
          value: Formatting.date(_startsAt),
          onTap: _submitting ? null : _pickStart,
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'New expiry: ${previewLicenseExpiry(_startsAt, _billingPeriod)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Amount paid',
          child: TextField(
            controller: _amount,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '${Formatting.tenantCurrency} ',
              hintText: catalogPrice == null
                  ? 'No list price set — enter manually'
                  : 'List price: ${Formatting.currency(catalogPrice)}',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Renewing…' : 'Renew',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

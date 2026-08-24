import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart'
    show CrmField, CrmMetaLine, CrmSheet, showCrmMessage, showCrmSheet;
import 'platform_providers.dart' show platformServiceProvider;
import 'platform_shell.dart' show PlatformListScaffold;

/// Pricing catalog for self-hosted licenses — separate from Subscription
/// Plans, which prices MoBilling SaaS itself.
///
/// Rows are seeded, one per [LicensePackages] value: this only ever reads and
/// edits prices/description, never creates or deletes.
final AutoDisposeFutureProvider<List<LicensePlan>> licensePlansProvider =
    FutureProvider.autoDispose<List<LicensePlan>>(
      (ref) => ref.watch(platformServiceProvider).licensePlans(),
    );

class LicensePlansScreen extends ConsumerWidget {
  const LicensePlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return PlatformListScaffold<LicensePlan>(
      title: 'License plans',
      value: ref.watch(licensePlansProvider),
      onRetry: () => ref.invalidate(licensePlansProvider),
      emptyIcon: Icons.vpn_key_outlined,
      emptyTitle: 'No license plans configured',
      footnote:
          'These three rows are fixed, one per package — edit prices per '
          'billing period. Leave a period blank if it is not offered.',
      itemBuilder: (context, plan) => ListTile(
        title: Text(plan.name, style: theme.textTheme.titleSmall),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              if (!plan.isActive) ...[
                const StatusChip('draft', dense: true),
                const SizedBox(width: Spacing.sm),
              ],
              Flexible(child: CrmMetaLine(_pricedPeriods(plan))),
            ],
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          size: 20,
          color: theme.colorScheme.outline,
        ),
        onTap: () => _edit(context, ref, plan),
      ),
    );
  }

  String _pricedPeriods(LicensePlan plan) {
    final priced = <String>[
      if (plan.monthlyPrice != null) 'monthly',
      if (plan.quarterlyPrice != null) 'quarterly',
      if (plan.semiAnnualPrice != null) 'semi-annual',
      if (plan.annualPrice != null) 'annual',
      if (plan.perpetualPrice != null) 'perpetual',
    ];
    return priced.isEmpty ? 'No pricing set' : priced.join(' · ');
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    LicensePlan plan,
  ) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _LicensePlanFormSheet(plan: plan),
    );
    if (saved == true) ref.invalidate(licensePlansProvider);
  }
}

class _LicensePlanFormSheet extends ConsumerStatefulWidget {
  const _LicensePlanFormSheet({required this.plan});

  final LicensePlan plan;

  @override
  ConsumerState<_LicensePlanFormSheet> createState() =>
      _LicensePlanFormSheetState();
}

class _LicensePlanFormSheetState extends ConsumerState<_LicensePlanFormSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _monthly = TextEditingController();
  final _quarterly = TextEditingController();
  final _semiAnnual = TextEditingController();
  final _annual = TextEditingController();
  final _perpetual = TextEditingController();
  late bool _isActive;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _name.text = plan.name;
    _description.text = plan.description ?? '';
    _monthly.text = _fmt(plan.monthlyPrice);
    _quarterly.text = _fmt(plan.quarterlyPrice);
    _semiAnnual.text = _fmt(plan.semiAnnualPrice);
    _annual.text = _fmt(plan.annualPrice);
    _perpetual.text = _fmt(plan.perpetualPrice);
    _isActive = plan.isActive;
  }

  static String _fmt(double? value) =>
      value == null ? '' : value.toStringAsFixed(0);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _monthly.dispose();
    _quarterly.dispose();
    _semiAnnual.dispose();
    _annual.dispose();
    _perpetual.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) =>
      c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(platformServiceProvider)
          .updateLicensePlan(
            widget.plan.id,
            name: _name.text.trim(),
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            monthlyPrice: _parse(_monthly),
            quarterlyPrice: _parse(_quarterly),
            semiAnnualPrice: _parse(_semiAnnual),
            annualPrice: _parse(_annual),
            perpetualPrice: _parse(_perpetual),
            isActive: _isActive,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Plan updated.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _priceField(String label, TextEditingController controller) =>
      CrmField(
        label: label,
        child: TextField(
          controller: controller,
          enabled: !_submitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '${Formatting.tenantCurrency} ',
            hintText: 'Not offered',
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CrmSheet(
      eyebrow: widget.plan.product.toUpperCase(),
      title: widget.plan.name,
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(controller: _name, enabled: !_submitting),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Description',
          child: TextField(
            controller: _description,
            enabled: !_submitting,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        const SizedBox(height: Spacing.md),
        _priceField('Monthly price', _monthly),
        const SizedBox(height: Spacing.md),
        _priceField('Quarterly price', _quarterly),
        const SizedBox(height: Spacing.md),
        _priceField('Semi-annual price', _semiAnnual),
        const SizedBox(height: Spacing.md),
        _priceField('Annual price', _annual),
        const SizedBox(height: Spacing.md),
        _priceField('Perpetual price', _perpetual),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Active', style: theme.textTheme.titleSmall),
          value: _isActive,
          onChanged: _submitting ? null : (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : 'Save',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

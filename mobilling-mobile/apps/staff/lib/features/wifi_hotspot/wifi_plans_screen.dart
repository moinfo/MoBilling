import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show CrmField, CrmMetaLine, CrmSheet, FilterStrip, showCrmSheet;
import 'wifi_hotspot_providers.dart';

/// Duration/data/speed bundles sold against a router's hotspot.
class WifiPlansScreen extends ConsumerStatefulWidget {
  const WifiPlansScreen({super.key});

  @override
  ConsumerState<WifiPlansScreen> createState() => _WifiPlansScreenState();
}

class _WifiPlansScreenState extends ConsumerState<WifiPlansScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  String? _routerId;

  void _reload() => _listKey.currentState?.reload();

  Future<void> _openForm({WifiPlan? plan}) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _PlanFormSheet(plan: plan, defaultRouterId: _routerId),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(WifiPlan plan) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this plan?'),
        content: Text('"${plan.name}" will no longer be offered for sale.'),
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
      await ref.read(wifiHotspotServiceProvider).deletePlan(plan.id);
      _reload();
      messenger.showSnackBar(const SnackBar(content: Text('Plan deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate = session?.can(WifiHotspotPermissions.plansCreate) ?? false;
    final canUpdate = session?.can(WifiHotspotPermissions.plansUpdate) ?? false;
    final canDelete = session?.can(WifiHotspotPermissions.plansDelete) ?? false;
    final routers = ref.watch(allRoutersProvider);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'WiFi Hotspot',
        title: 'Plans',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add plan',
                onPressed: () => _openForm(),
              )
            : null,
      ),
      body: Column(
        children: [
          routers.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (rows) {
              if (rows.length < 2) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  0,
                ),
                child: FilterStrip(
                  options: [
                    (null, 'All routers'),
                    for (final r in rows) (r.id, r.name),
                  ],
                  selected: _routerId,
                  onSelect: (v) {
                    setState(() => _routerId = v);
                    _reload();
                  },
                ),
              );
            },
          ),
          Expanded(
            child: PagedListView<WifiPlan>(
              key: _listKey,
              fetch: (page) => ref
                  .read(wifiHotspotServiceProvider)
                  .plans(mikrotikRouterId: _routerId, page: page),
              itemBuilder: (context, plan) => _PlanCard(
                plan: plan,
                canUpdate: canUpdate,
                canDelete: canDelete,
                onTap: canUpdate ? () => _openForm(plan: plan) : null,
                onDelete: () => _delete(plan),
              ),
              emptyIcon: Icons.sell_outlined,
              emptyTitle: 'No plans yet',
              emptyMessage: canCreate
                  ? 'Add a plan so staff can start selling vouchers.'
                  : 'None configured yet.',
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.canUpdate,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  final WifiPlan plan;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(
          plan.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: CrmMetaLine(
            [
              plan.durationLabel,
              plan.dataCapLabel,
              if (plan.routerName != null) plan.routerName!,
              if (!plan.isActive) 'Inactive',
            ].join(' · '),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Money(plan.price),
            if (canDelete) ...[
              const SizedBox(width: Spacing.xs),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
                onPressed: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Add or edit a plan. Needs at least one of duration or data cap — the
/// backend's own `required_without` rule, enforced here too so the error
/// shows before a round trip.
class _PlanFormSheet extends ConsumerStatefulWidget {
  const _PlanFormSheet({this.plan, this.defaultRouterId});

  final WifiPlan? plan;
  final String? defaultRouterId;

  @override
  ConsumerState<_PlanFormSheet> createState() => _PlanFormSheetState();
}

class _PlanFormSheetState extends ConsumerState<_PlanFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _durationValue;
  late final TextEditingController _dataCapMb;
  late final TextEditingController _speedLimit;
  late final TextEditingController _price;
  late final TextEditingController _hotspotProfile;
  String? _routerId;
  String _durationUnit = 'days';
  late bool _isActive;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _name = TextEditingController(text: p?.name ?? '');
    _durationValue = TextEditingController(
      text: p?.durationValue == null ? '' : '${p!.durationValue}',
    );
    _dataCapMb = TextEditingController(
      text: p?.dataCapMb == null ? '' : '${p!.dataCapMb}',
    );
    _speedLimit = TextEditingController(
      text: p?.speedLimitMbps == null ? '' : Formatting.amount(p!.speedLimitMbps),
    );
    _price = TextEditingController(
      text: p == null ? '' : Formatting.amount(p.price),
    );
    _hotspotProfile = TextEditingController(text: p?.hotspotProfile ?? '');
    _routerId = p?.mikrotikRouterId ?? widget.defaultRouterId;
    _durationUnit = p?.durationUnit ?? 'days';
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _durationValue.dispose();
    _dataCapMb.dispose();
    _speedLimit.dispose();
    _price.dispose();
    _hotspotProfile.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim().replaceAll(',', ''));
    final durationValue = int.tryParse(_durationValue.text.trim());
    final dataCapMb = int.tryParse(_dataCapMb.text.trim());
    final speedLimit = _speedLimit.text.trim().isEmpty
        ? null
        : double.tryParse(_speedLimit.text.trim());

    if (_routerId == null) {
      setState(() => _error = 'Choose a router.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }
    if (durationValue == null && dataCapMb == null) {
      setState(
        () => _error = 'Set a duration, a data cap, or both — at least one.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final service = ref.read(wifiHotspotServiceProvider);
      final hotspotProfile = _hotspotProfile.text.trim().isEmpty
          ? null
          : _hotspotProfile.text.trim();
      if (_editing) {
        await service.updatePlan(
          widget.plan!.id,
          mikrotikRouterId: _routerId!,
          name: name,
          price: price,
          durationValue: durationValue,
          durationUnit: durationValue == null ? null : _durationUnit,
          dataCapMb: dataCapMb,
          speedLimitMbps: speedLimit,
          hotspotProfile: hotspotProfile,
          isActive: _isActive,
        );
      } else {
        await service.createPlan(
          mikrotikRouterId: _routerId!,
          name: name,
          price: price,
          durationValue: durationValue,
          durationUnit: durationValue == null ? null : _durationUnit,
          dataCapMb: dataCapMb,
          speedLimitMbps: speedLimit,
          hotspotProfile: hotspotProfile,
          isActive: _isActive,
        );
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_editing ? 'Plan updated.' : 'Plan added.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final routers = ref.watch(allRoutersProvider);

    return CrmSheet(
      eyebrow: 'WiFi Hotspot',
      title: _editing ? 'Edit plan' : 'New plan',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        routers.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorBanner(
            message: e is ApiException
                ? 'Could not load routers: ${e.message}'
                : 'Could not load routers.',
          ),
          data: (rows) => CrmField(
            label: 'Router',
            child: DropdownButtonFormField<String>(
              initialValue: rows.any((r) => r.id == _routerId)
                  ? _routerId
                  : null,
              isExpanded: true,
              hint: const Text('Choose a router'),
              items: [
                for (final r in rows)
                  DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _routerId = v),
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(hintText: 'e.g. 1 Day Unlimited'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: CrmField(
                label: 'Duration (optional)',
                child: TextField(
                  controller: _durationValue,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              flex: 3,
              child: CrmField(
                label: 'Unit',
                child: DropdownButtonFormField<String>(
                  initialValue: _durationUnit,
                  isExpanded: true,
                  items: [
                    for (final (value, label) in WifiDurationUnits.values)
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _durationUnit = v ?? _durationUnit),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Data cap in MB (optional)',
          child: TextField(
            controller: _dataCapMb,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 2048 for 2GB'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Speed limit in Mbps (optional)',
          child: TextField(
            controller: _speedLimit,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Price',
          child: TextField(
            controller: _price,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '${Formatting.tenantCurrency} ',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Hotspot profile (optional)',
          child: TextField(controller: _hotspotProfile, enabled: !_busy),
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          value: _isActive,
          onChanged: _busy ? null : (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _editing ? 'Save changes' : 'Add plan',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

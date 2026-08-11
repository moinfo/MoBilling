import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../navigation/admin_menu.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmDetailRow;
import 'platform_providers.dart';

/// Every tenant on the platform.
class TenantsScreen extends ConsumerStatefulWidget {
  const TenantsScreen({super.key});

  @override
  ConsumerState<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends ConsumerState<TenantsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
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
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search tenant name or email',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) => ref.read(platformServiceProvider).tenants(
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    page: page,
                  ),
              itemBuilder: (context, tenant) => Card(
                child: ListTile(
                  title: Text(tenant.name),
                  subtitle: Text(
                    [
                      tenant.email ?? '',
                      if (tenant.customDomain != null) tenant.customDomain!,
                      if (tenant.daysRemaining != null)
                        '${tenant.daysRemaining}d left',
                      if (tenant.smsBalance != null)
                        '${tenant.smsBalance} SMS',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusChip(tenant.chipStatus, dense: true),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => context.push(AdminRoutes.tenantPath(tenant.id)),
                ),
              ),
              emptyIcon: Icons.apartment_outlined,
              emptyTitle: 'No tenants found',
            ),
          ),
        ],
      ),
    );
  }
}

/// One tenant: profile, users, subscriptions, SMS credit, and the per-tenant
/// email/SMS/template settings that the web reaches the same way.
class TenantDetailScreen extends ConsumerWidget {
  const TenantDetailScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(platformTenantProvider(tenantId));
    final users = ref.watch(tenantUsersProvider(tenantId));
    final subscriptions = ref.watch(tenantSubscriptionsProvider(tenantId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(tenant.valueOrNull?.name ?? 'Tenant')),
      body: CrmAsyncView(
        value: tenant,
        errorTitle: 'Could not load this tenant',
        onRetry: () => ref.invalidate(platformTenantProvider(tenantId)),
        builder: (t) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(t.name,
                              style: theme.textTheme.titleMedium),
                        ),
                        StatusChip(t.chipStatus, dense: true),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    if (t.email != null) CrmDetailRow('Email', t.email!),
                    if (t.phone != null) CrmDetailRow('Phone', t.phone!),
                    if (t.customDomain != null)
                      CrmDetailRow('Domain', t.customDomain!),
                    if (t.currency != null)
                      CrmDetailRow('Currency', t.currency!),
                    if (t.subscriptionStatus != null)
                      CrmDetailRow(
                          'Subscription',
                          '${t.subscriptionStatus}'
                          '${t.daysRemaining == null ? '' : ' · ${t.daysRemaining}d left'}'),
                    CrmDetailRow('SMS balance', '${t.smsBalance ?? 0}'),
                    if (t.createdAt != null)
                      CrmDetailRow('Joined', Formatting.date(t.createdAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),

            // Actions that change a tenant's standing.
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add_card_outlined),
                    title: const Text('Recharge SMS'),
                    onTap: () => _smsAdjust(context, ref, recharge: true),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.remove_circle_outline),
                    title: const Text('Deduct SMS'),
                    onTap: () => _smsAdjust(context, ref, recharge: false),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.more_time_outlined),
                    title: const Text('Extend subscription'),
                    onTap: () => _extend(context, ref),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: const Text('Email settings'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.push(AdminRoutes.tenantEmailPath(tenantId)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.sms_outlined),
                    title: const Text('SMS settings'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.push(AdminRoutes.tenantSmsPath(tenantId)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Email templates'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context
                        .push(AdminRoutes.tenantTemplatesPath(tenantId)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      t.isActive ? Icons.block : Icons.play_circle_outline,
                      color: t.isActive
                          ? theme.colorScheme.error
                          : context.statusColors.settled,
                    ),
                    title: Text(
                      t.isActive ? 'Deactivate tenant' : 'Reactivate tenant',
                      style: TextStyle(
                          color: t.isActive ? theme.colorScheme.error : null),
                    ),
                    subtitle: t.isActive
                        ? const Text('Locks out every user of this tenant')
                        : null,
                    onTap: () => _toggleActive(context, ref, t),
                  ),
                ],
              ),
            ),

            // Subscriptions, with confirm-payment on anything pending.
            subscriptions.maybeWhen(
              data: (records) => records.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: Spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Subscriptions',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: Spacing.sm),
                          Card(
                            child: Column(
                              children: [
                                for (final (i, record) in records.indexed) ...[
                                  if (i > 0) const Divider(height: 1),
                                  ListTile(
                                    dense: true,
                                    title:
                                        Text(record.planName ?? 'Subscription'),
                                    subtitle: Text(
                                      [
                                        if (record.startsAt != null &&
                                            record.endsAt != null)
                                          '${Formatting.date(record.startsAt)} – ${Formatting.date(record.endsAt)}',
                                        Formatting.currency(record.amount),
                                      ].join(' · '),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    trailing: record.awaitingConfirmation
                                        ? FilledButton.tonal(
                                            onPressed: () => _confirm(
                                                context, ref, record.id),
                                            child: const Text('Confirm'),
                                          )
                                        : StatusChip(record.status,
                                            dense: true),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),

            // Their staff users.
            users.maybeWhen(
              data: (items) => items.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: Spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Users (${items.length})',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: Spacing.sm),
                          Card(
                            child: Column(
                              children: [
                                for (final (i, user) in items.indexed) ...[
                                  if (i > 0) const Divider(height: 1),
                                  ListTile(
                                    dense: true,
                                    title: Text(user.name),
                                    subtitle: Text(
                                      [
                                        user.email ?? '',
                                        user.roleName ?? '',
                                        if (!user.isActive) 'deactivated',
                                      ]
                                          .where((s) => s.isNotEmpty)
                                          .join(' · '),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(
                                        user.isActive
                                            ? Icons.toggle_on
                                            : Icons.toggle_off_outlined,
                                        color: user.isActive
                                            ? context.statusColors.settled
                                            : null,
                                      ),
                                      onPressed: () =>
                                          _toggleUser(context, ref, user.id),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(
      BuildContext context, WidgetRef ref, PlatformTenant t) async {
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.isActive ? 'Deactivate ${t.name}?' : 'Reactivate ${t.name}?'),
        content: Text(t.isActive
            ? 'Every user of this tenant will be blocked at sign-in until it is reactivated.'
            : 'Users of this tenant will be able to sign in again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.isActive ? 'Deactivate' : 'Reactivate')),
        ],
      ),
    );
    if (sure != true) return;

    try {
      await ref.read(platformServiceProvider).toggleTenantActive(tenantId);
      ref.invalidate(platformTenantProvider(tenantId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleUser(
      BuildContext context, WidgetRef ref, String userId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(platformServiceProvider)
          .toggleTenantUserActive(tenantId, userId);
      ref.invalidate(tenantUsersProvider(tenantId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirm(
      BuildContext context, WidgetRef ref, String subscriptionId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(platformServiceProvider)
          .confirmSubscriptionPayment(subscriptionId);
      ref.invalidate(tenantSubscriptionsProvider(tenantId));
      ref.invalidate(platformTenantProvider(tenantId));
      messenger.showSnackBar(
          const SnackBar(content: Text('Payment confirmed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _smsAdjust(BuildContext context, WidgetRef ref,
      {required bool recharge}) async {
    final quantity = TextEditingController();
    final notes = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recharge ? 'Recharge SMS' : 'Deduct SMS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantity,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Messages'),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(recharge ? 'Recharge' : 'Deduct')),
        ],
      ),
    );
    if (ok != true) return;

    final amount = int.tryParse(quantity.text.trim());
    if (amount == null || amount <= 0) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Enter a valid quantity.')));
      return;
    }

    try {
      final service = ref.read(platformServiceProvider);
      final reason = notes.text.trim().isEmpty ? null : notes.text.trim();
      // Separate endpoints, not a signed amount — a sign slip cannot drain a
      // tenant's balance.
      recharge
          ? await service.rechargeSms(tenantId, amount, notes: reason)
          : await service.deductSms(tenantId, amount, notes: reason);
      ref.invalidate(platformTenantProvider(tenantId));
      messenger.showSnackBar(SnackBar(
          content: Text(recharge
              ? 'Added $amount messages.'
              : 'Deducted $amount messages.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _extend(BuildContext context, WidgetRef ref) async {
    final days = TextEditingController(text: '30');
    final notes = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Extend subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: days,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Days'),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Extend')),
        ],
      ),
    );
    if (ok != true) return;

    final amount = int.tryParse(days.text.trim());
    if (amount == null || amount <= 0) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Enter valid days.')));
      return;
    }

    try {
      await ref.read(platformServiceProvider).extendSubscription(
            tenantId,
            days: amount,
            notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
          );
      ref.invalidate(platformTenantProvider(tenantId));
      ref.invalidate(tenantSubscriptionsProvider(tenantId));
      messenger.showSnackBar(
          SnackBar(content: Text('Extended by $amount days.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

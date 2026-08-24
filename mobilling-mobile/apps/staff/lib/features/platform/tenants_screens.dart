import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../navigation/admin_menu.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmDetailRow,
        CrmField,
        CrmMetaLine,
        CrmStatusLine;
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
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Platform',
        title: 'Tenants',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search tenant name or email',
          onChanged: _onSearchChanged,
        ),
      ),
      body: PagedListView(
        key: _listKey,
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        fetch: (page) => ref
            .read(platformServiceProvider)
            .tenants(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        itemBuilder: (context, tenant) => Card(
          child: ListTile(
            title: Text(
              tenant.name,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: CrmStatusLine(
                status: tenant.chipStatus,
                meta: [
                  tenant.email ?? '',
                  if (tenant.customDomain != null) tenant.customDomain!,
                  if (tenant.daysRemaining != null)
                    '${tenant.daysRemaining}d left',
                  if (tenant.smsBalance != null)
                    '${Formatting.integer(tenant.smsBalance)} sms',
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: 20,
              color: scheme.outline,
            ),
            onTap: () => context.push(AdminRoutes.tenantPath(tenant.id)),
          ),
        ),
        emptyIcon: Icons.apartment_outlined,
        emptyTitle: 'No tenants found',
        emptyMessage: 'Nothing matches this search.',
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
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Tenant',
        title: tenant.valueOrNull?.name ?? 'Tenant',
      ),
      body: CrmAsyncView(
        value: tenant,
        errorTitle: 'Could not load this tenant',
        onRetry: () => ref.invalidate(platformTenantProvider(tenantId)),
        builder: (t) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.xl,
          ),
          children: [
            // Standing first: how long they have left, and how much they can
            // still send. Everything else on the screen explains those two.
            StatRail(
              items: [
                StatRailItem(
                  label: 'Days left',
                  value: t.daysRemaining == null
                      ? '—'
                      : Formatting.integer(t.daysRemaining),
                  emphasis: switch (t.daysRemaining) {
                    null => null,
                    final int d when d < 0 => status.overdue,
                    final int d when d <= 7 => status.attention,
                    _ => null,
                  },
                ),
                StatRailItem(
                  label: 'SMS',
                  value: Formatting.integer(t.smsBalance ?? 0),
                  emphasis: (t.smsBalance ?? 0) <= 0 ? status.overdue : null,
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            SectionHeader(
              'Profile',
              trailing: StatusChip(t.chipStatus, dense: true),
            ),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            '${t.daysRemaining == null ? '' : ' · ${t.daysRemaining}d left'}',
                      ),
                    if (t.createdAt != null)
                      CrmDetailRow('Joined', Formatting.date(t.createdAt)),
                  ],
                ),
              ),
            ),

            // Actions that change a tenant's standing.
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Actions'),
            const SizedBox(height: Spacing.sm),
            CrmCardList(
              children: [
                ListTile(
                  leading: const Icon(Icons.add_card_outlined, size: 20),
                  title: Text(
                    'Recharge SMS',
                    style: theme.textTheme.titleSmall,
                  ),
                  onTap: () => _smsAdjust(context, ref, recharge: true),
                ),
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline, size: 20),
                  title: Text('Deduct SMS', style: theme.textTheme.titleSmall),
                  onTap: () => _smsAdjust(context, ref, recharge: false),
                ),
                ListTile(
                  leading: const Icon(Icons.more_time_outlined, size: 20),
                  title: Text(
                    'Extend subscription',
                    style: theme.textTheme.titleSmall,
                  ),
                  onTap: () => _extend(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.mail_outline, size: 20),
                  title: Text(
                    'Email settings',
                    style: theme.textTheme.titleSmall,
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.outline,
                  ),
                  onTap: () =>
                      context.push(AdminRoutes.tenantEmailPath(tenantId)),
                ),
                ListTile(
                  leading: const Icon(Icons.sms_outlined, size: 20),
                  title: Text(
                    'SMS settings',
                    style: theme.textTheme.titleSmall,
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.outline,
                  ),
                  onTap: () =>
                      context.push(AdminRoutes.tenantSmsPath(tenantId)),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined, size: 20),
                  title: Text(
                    'Email templates',
                    style: theme.textTheme.titleSmall,
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.outline,
                  ),
                  onTap: () =>
                      context.push(AdminRoutes.tenantTemplatesPath(tenantId)),
                ),
                ListTile(
                  leading: Icon(
                    t.isActive ? Icons.block : Icons.play_circle_outline,
                    size: 20,
                    color: t.isActive ? scheme.error : status.settled,
                  ),
                  title: Text(
                    t.isActive ? 'Deactivate tenant' : 'Reactivate tenant',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: t.isActive ? scheme.error : null,
                    ),
                  ),
                  subtitle: t.isActive
                      ? Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Locks out every user of this tenant',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => _toggleActive(context, ref, t),
                ),
              ],
            ),

            // Subscriptions, with confirm-payment on anything pending.
            subscriptions.maybeWhen(
              data: (records) => records.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: Spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionHeader('Subscriptions'),
                          const SizedBox(height: Spacing.sm),
                          CrmCardList(
                            children: [
                              for (final record in records)
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    record.planName ?? 'Subscription',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        StatusChip(record.status, dense: true),
                                        const SizedBox(width: Spacing.sm),
                                        // A row waiting on a decision gives
                                        // its trailing column to the button,
                                        // so the amount moves up here.
                                        if (record.awaitingConfirmation) ...[
                                          Money(
                                            record.amount,
                                            scale: MoneyScale.dense,
                                            showCode: false,
                                          ),
                                          const SizedBox(width: Spacing.sm),
                                        ],
                                        if (record.startsAt != null &&
                                            record.endsAt != null)
                                          Flexible(
                                            child: CrmMetaLine(
                                              '${Formatting.date(record.startsAt)} – '
                                              '${Formatting.date(record.endsAt)}',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  trailing: record.awaitingConfirmation
                                      ? FilledButton.tonal(
                                          onPressed: () =>
                                              _confirm(context, ref, record.id),
                                          child: const Text('Confirm'),
                                        )
                                      : Money(record.amount),
                                ),
                            ],
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SectionHeader(
                            'Users',
                            trailing: Text(
                              Formatting.integer(items.length),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          CrmCardList(
                            children: [
                              for (final user in items)
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    user.name,
                                    style: theme.textTheme.titleSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: CrmStatusLine(
                                      status: user.isActive
                                          ? 'active'
                                          : 'deactivated',
                                      meta: [
                                        user.email ?? '',
                                        user.roleName ?? '',
                                      ].where((s) => s.isNotEmpty).join(' · '),
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      user.isActive
                                          ? Icons.toggle_on
                                          : Icons.toggle_off_outlined,
                                      color: user.isActive
                                          ? status.settled
                                          : null,
                                    ),
                                    tooltip: user.isActive
                                        ? 'Deactivate'
                                        : 'Reactivate',
                                    onPressed: () =>
                                        _toggleUser(context, ref, user.id),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    PlatformTenant t,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t.isActive ? 'Deactivate ${t.name}?' : 'Reactivate ${t.name}?',
          style: Type.display(22, color: scheme.onSurface),
        ),
        content: Text(
          t.isActive
              ? 'Every user of this tenant will be blocked at sign-in until it is reactivated.'
              : 'Users of this tenant will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.isActive ? 'Deactivate tenant' : 'Reactivate tenant'),
          ),
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
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
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
    BuildContext context,
    WidgetRef ref,
    String subscriptionId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(platformServiceProvider)
          .confirmSubscriptionPayment(subscriptionId);
      ref.invalidate(tenantSubscriptionsProvider(tenantId));
      ref.invalidate(platformTenantProvider(tenantId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Payment confirmed.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _smsAdjust(
    BuildContext context,
    WidgetRef ref, {
    required bool recharge,
  }) async {
    final quantity = TextEditingController();
    final notes = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          recharge ? 'Recharge SMS' : 'Deduct SMS',
          style: Type.display(22, color: scheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CrmField(
              label: 'Messages',
              child: TextField(
                controller: quantity,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'How many'),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Reason',
              child: TextField(
                controller: notes,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Why the balance is changing',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(recharge ? 'Recharge' : 'Deduct'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final amount = int.tryParse(quantity.text.trim());
    if (amount == null || amount <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity.')),
      );
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            recharge ? 'Added $amount messages.' : 'Deducted $amount messages.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _extend(BuildContext context, WidgetRef ref) async {
    final days = TextEditingController(text: '30');
    final notes = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Extend subscription',
          style: Type.display(22, color: scheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CrmField(
              label: 'Days',
              child: TextField(
                controller: days,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'How many days'),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Reason',
              child: TextField(
                controller: notes,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Why it is being extended',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Extend'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final amount = int.tryParse(days.text.trim());
    if (amount == null || amount <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter valid days.')),
      );
      return;
    }

    try {
      await ref
          .read(platformServiceProvider)
          .extendSubscription(
            tenantId,
            days: amount,
            notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
          );
      ref.invalidate(platformTenantProvider(tenantId));
      ref.invalidate(tenantSubscriptionsProvider(tenantId));
      messenger.showSnackBar(
        SnackBar(content: Text('Extended by $amount days.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ---------------------------------------------------------------------------
// Private building blocks (candidates for mobilling_ui)
// ---------------------------------------------------------------------------

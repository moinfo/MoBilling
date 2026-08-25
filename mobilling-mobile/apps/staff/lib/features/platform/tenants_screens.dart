import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../navigation/admin_menu.dart';
import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmDetailRow,
        CrmField,
        CrmMetaLine,
        CrmSheet,
        CrmStatusLine,
        showCrmSheet;
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

  Future<void> _newTenant(BuildContext context) async {
    final created = await Navigator.of(context).push<PlatformTenant>(
      MaterialPageRoute(builder: (_) => const _TenantFormScreen()),
    );
    if (created != null) _listKey.currentState?.reload();
  }

  Future<void> _promoteClient(BuildContext context) async {
    final promoted = await Navigator.of(context).push<PlatformTenant>(
      MaterialPageRoute(builder: (_) => const _PromoteClientScreen()),
    );
    if (promoted == null) return;
    _listKey.currentState?.reload();
    if (!context.mounted) return;
    await _offerImpersonateAfterPromote(context, ref, promoted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Platform',
        title: 'Tenants',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkActionButton(
              icon: Icons.arrow_upward_outlined,
              tooltip: 'Promote a client to a tenant',
              onPressed: () => _promoteClient(context),
            ),
            const SizedBox(width: Spacing.sm),
            InkActionButton(
              icon: Icons.add,
              tooltip: 'New tenant',
              onPressed: () => _newTenant(context),
            ),
          ],
        ),
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
                  leading: const Icon(Icons.edit_outlined, size: 20),
                  title: Text('Edit tenant', style: theme.textTheme.titleSmall),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.outline,
                  ),
                  onTap: () => _editTenant(context, ref, t),
                ),
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
                  leading: const Icon(Icons.key_outlined, size: 20),
                  title: Text(
                    'Permission grants',
                    style: theme.textTheme.titleSmall,
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.outline,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _TenantPermissionsScreen(
                        tenantId: tenantId,
                        tenantName: t.name,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.login, size: 20),
                  title: Text(
                    'Sign in as tenant admin',
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Swaps your session for theirs',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  onTap: () => _confirmImpersonateTenant(context, ref, t),
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
                                  trailing: Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: scheme.outline,
                                  ),
                                  onTap: () =>
                                      _openUserSheet(context, ref, user),
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

  Future<void> _editTenant(
    BuildContext context,
    WidgetRef ref,
    PlatformTenant t,
  ) async {
    final saved = await Navigator.of(context).push<PlatformTenant>(
      MaterialPageRoute(builder: (_) => _TenantFormScreen(existing: t)),
    );
    if (saved != null) ref.invalidate(platformTenantProvider(tenantId));
  }

  Future<void> _openUserSheet(
    BuildContext context,
    WidgetRef ref,
    StaffUser user,
  ) => showCrmSheet(
    context: context,
    builder: (sheetContext) => CrmSheet(
      eyebrow: 'User',
      title: user.name,
      children: [
        ListTile(
          leading: Icon(
            user.isActive ? Icons.toggle_off_outlined : Icons.toggle_on,
          ),
          title: Text(user.isActive ? 'Deactivate' : 'Reactivate'),
          onTap: () {
            Navigator.pop(sheetContext);
            _toggleUser(context, ref, user.id);
          },
        ),
        ListTile(
          enabled: user.isActive,
          leading: const Icon(Icons.login),
          title: const Text('Sign in as this user'),
          subtitle: user.isActive ? null : const Text('Reactivate them first'),
          onTap: () {
            Navigator.pop(sheetContext);
            _confirmImpersonateUser(context, ref, tenantId, user.id, user.name);
          },
        ),
      ],
    ),
  );
}

/// Runs an impersonation call and swaps the session on success, sharing every
/// error path between "sign in as the tenant admin" and "sign in as one of
/// its users". Callers own their own confirmation UI first.
Future<void> _adoptImpersonation(
  BuildContext context,
  WidgetRef ref,
  Future<Map<String, dynamic>> Function() call,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final body = await call();
    // Neither impersonation endpoint reports `user_type` (there is no column
    // for it — it only exists on the login response) or `permissions`;
    // forcing `tenant` here is safe because both endpoints only ever mint a
    // token for a tenant-side `User`, never a `ClientUser`.
    // `SessionController.impersonate` refreshes permissions from `/auth/me`
    // under the new token right after adopting it.
    final session = AuthSession.fromJson({...body, 'user_type': 'tenant'});
    await ref.read(sessionControllerProvider).impersonate(session);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// `AlertDialog` shared by every impersonation entry point. Says plainly what
/// is about to happen and how to get back — "Back to {name}" in the account
/// sheet, next to Sign out.
Future<bool> _confirmImpersonateDialog(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: Type.display(22, color: scheme.onSurface)),
      content: Text(
        '$body\n\nTo return, open the account sheet (tap your avatar) and '
        'use "Back to …" — it stays there until you do.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign in'),
        ),
      ],
    ),
  );
  return sure ?? false;
}

Future<void> _confirmImpersonateTenant(
  BuildContext context,
  WidgetRef ref,
  PlatformTenant t,
) async {
  final sure = await _confirmImpersonateDialog(
    context,
    title: 'Sign in as ${t.name}?',
    body: 'This swaps your session for that tenant\'s admin account.',
  );
  if (!sure) return;
  if (!context.mounted) return;
  await _adoptImpersonation(
    context,
    ref,
    () => ref.read(platformServiceProvider).impersonateTenant(t.id),
  );
}

Future<void> _confirmImpersonateUser(
  BuildContext context,
  WidgetRef ref,
  String tenantId,
  String userId,
  String userName,
) async {
  final sure = await _confirmImpersonateDialog(
    context,
    title: 'Sign in as $userName?',
    body: 'This swaps your session for their account.',
  );
  if (!sure) return;
  if (!context.mounted) return;
  await _adoptImpersonation(
    context,
    ref,
    () => ref
        .read(platformServiceProvider)
        .impersonateTenantUser(tenantId, userId),
  );
}

/// After "Promote from Client" succeeds, offer to sign in as the new tenant
/// right away — mirroring the inline banner web shows on the same success
/// (`Tenants.tsx`'s `promotedTenant` alert: "Log in as this tenant now?").
Future<void> _offerImpersonateAfterPromote(
  BuildContext context,
  WidgetRef ref,
  PlatformTenant tenant,
) async {
  final scheme = Theme.of(context).colorScheme;
  final signIn = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        'Tenant "${tenant.name}" created',
        style: Type.display(22, color: scheme.onSurface),
      ),
      content: const Text(
        'Sign in as this tenant now to finish branding and product setup? '
        'The account sheet (tap your avatar) can bring you back once you\'re '
        'done.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign in now'),
        ),
      ],
    ),
  );
  if (signIn != true) return;
  if (!context.mounted) return;
  await _adoptImpersonation(
    context,
    ref,
    () => ref.read(platformServiceProvider).impersonateTenant(tenant.id),
  );
}

// ---------------------------------------------------------------------------
// Create / edit a tenant — `POST /admin/tenants` and `PUT /admin/tenants/{id}`,
// the web's `Tenants.tsx` modal (`TenantForm`) folded into a full screen: a
// phone has no modal-sized surface worth the name.
// ---------------------------------------------------------------------------

class _TenantFormScreen extends ConsumerStatefulWidget {
  const _TenantFormScreen({this.existing});

  /// Null creates; anything else edits that tenant. Address and tax ID are
  /// blank-safe either way: the API only overwrites a field that is actually
  /// present in the request body, so leaving one empty on edit keeps the
  /// tenant's existing value rather than clearing it.
  final PlatformTenant? existing;

  @override
  ConsumerState<_TenantFormScreen> createState() => _TenantFormScreenState();
}

class _TenantFormScreenState extends ConsumerState<_TenantFormScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _taxId = TextEditingController();
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();

  List<PlatformCurrency> _currencies = const [];
  String? _currency;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _currency = t?.currency ?? 'TZS';
    if (t != null) {
      _name.text = t.name;
      _email.text = t.email ?? '';
      _phone.text = t.phone ?? '';
      _address.text = t.address ?? '';
      _taxId.text = t.taxId ?? '';
    }
    _loadCurrencies();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _email,
      _phone,
      _address,
      _taxId,
      _adminName,
      _adminEmail,
      _adminPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCurrencies() async {
    try {
      final list = await ref.read(platformServiceProvider).currencies();
      if (mounted) {
        setState(() => _currencies = list.where((c) => c.isActive).toList());
      }
    } on ApiException {
      // The dropdown below falls back to just the current/default code.
    }
  }

  String? _value(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'A company name is required.';
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim())) {
      return 'That company email does not look right.';
    }
    if (!_isEdit) {
      if (_adminName.text.trim().isEmpty) return 'The admin name is required.';
      if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_adminEmail.text.trim())) {
        return 'That admin email does not look right.';
      }
      if (_adminPassword.text.length < 8) {
        return 'The admin password needs at least 8 characters.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final existing = widget.existing;

    try {
      final service = ref.read(platformServiceProvider);
      final saved = existing == null
          ? await service.createTenant(
              name: _name.text.trim(),
              email: _email.text.trim(),
              phone: _value(_phone),
              address: _value(_address),
              taxId: _value(_taxId),
              currency: _currency,
              adminName: _adminName.text.trim(),
              adminEmail: _adminEmail.text.trim(),
              adminPassword: _adminPassword.text,
            )
          : await service.updateTenant(
              existing.id,
              name: _name.text.trim(),
              email: _email.text.trim(),
              phone: _value(_phone),
              address: _value(_address),
              taxId: _value(_taxId),
              currency: _currency,
            );

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? '${saved.name} created.'
                : '${saved.name} saved.',
          ),
        ),
      );
      navigator.pop(saved);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }

  /// The current currency plus whatever the catalogue offers, so the field
  /// never points at a value that isn't one of its own items — which
  /// `DropdownButtonFormField` asserts on — even before the catalogue call
  /// returns, or if that call fails outright.
  List<String> get _currencyCodes =>
      {..._currencies.map((c) => c.code), ?_currency}.toList()..sort();

  String _currencyLabel(String code) {
    for (final c in _currencies) {
      if (c.code == code) return c.name == null ? code : '$code — ${c.name}';
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final codes = _currencyCodes;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: _isEdit ? widget.existing!.name : 'Tenants',
        title: _isEdit ? 'Edit tenant' : 'New tenant',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],
          CrmField(
            label: 'Company name',
            child: TextField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Acme Ltd'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Company email',
            child: TextField(
              controller: _email,
              enabled: !_saving,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'info@acme.com'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Phone',
            child: TextField(
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: '+255 7xx xxx xxx'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Address',
            child: TextField(
              controller: _address,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Street, city'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Tax ID / TIN',
            child: TextField(
              controller: _taxId,
              enabled: !_saving,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'e.g. 123-456-789'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Currency',
            child: DropdownButtonFormField<String>(
              initialValue: codes.contains(_currency) ? _currency : null,
              isExpanded: true,
              items: [
                for (final code in codes)
                  DropdownMenuItem(
                    value: code,
                    child: Text(
                      _currencyLabel(code),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _saving ? null : (v) => setState(() => _currency = v),
            ),
          ),
          if (!_isEdit) ...[
            const SizedBox(height: Spacing.lg),
            Text(
              'That tenant\'s first admin account',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Admin name',
              child: TextField(
                controller: _adminName,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'John Doe'),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Admin email',
              child: TextField(
                controller: _adminEmail,
                enabled: !_saving,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'admin@acme.com'),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Admin password',
              child: TextField(
                controller: _adminPassword,
                enabled: !_saving,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Min. 8 characters',
                ),
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: _saving
                ? 'Saving…'
                : (_isEdit ? 'Save changes' : 'Create tenant'),
            busy: _saving,
            icon: _isEdit ? Icons.save_outlined : Icons.add_business_outlined,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Promote an existing client into its own independent, white-label tenant —
// `POST /admin/tenants/promote-from-client`, the web's `PromoteClientForm`.
// A search step picks the client (cross-tenant — a super admin has no
// tenant of their own to scope the regular client list to), then a form
// step, prefilled from the pick but fully editable, same as web.
// ---------------------------------------------------------------------------

class _PromoteClientScreen extends ConsumerStatefulWidget {
  const _PromoteClientScreen();

  @override
  ConsumerState<_PromoteClientScreen> createState() =>
      _PromoteClientScreenState();
}

class _PromoteClientScreenState extends ConsumerState<_PromoteClientScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ClientSearchResult> _results = const [];
  bool _searching = false;

  ClientSearchResult? _selected;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _taxId = TextEditingController();
  final _currency = TextEditingController(text: 'TZS');
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _search,
      _name,
      _email,
      _phone,
      _address,
      _taxId,
      _currency,
      _adminName,
      _adminEmail,
      _adminPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);
    try {
      final results = await ref
          .read(platformServiceProvider)
          .searchClients(query);
      if (mounted) setState(() => _results = results);
    } on ApiException {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(ClientSearchResult client) {
    setState(() {
      _selected = client;
      _name.text = client.name;
      _email.text = client.email ?? '';
      _phone.text = client.phone ?? '';
      _address.text = client.address ?? '';
      _taxId.text = client.taxId ?? '';
      _currency.text = client.tenantCurrency ?? 'TZS';
    });
  }

  void _backToSearch() {
    setState(() {
      _selected = null;
      _error = null;
    });
  }

  String? _value(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'A company name is required.';
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim())) {
      return 'That company email does not look right.';
    }
    if (_adminName.text.trim().isEmpty) return 'The admin name is required.';
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_adminEmail.text.trim())) {
      return 'That admin email does not look right.';
    }
    if (_adminPassword.text.length < 8) {
      return 'The admin password needs at least 8 characters.';
    }
    return null;
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null) return;
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);

    try {
      final tenant = await ref
          .read(platformServiceProvider)
          .promoteClientToTenant(
            clientId: selected.id,
            name: _name.text.trim(),
            email: _email.text.trim(),
            phone: _value(_phone),
            address: _value(_address),
            taxId: _value(_taxId),
            currency: _value(_currency),
            adminName: _adminName.text.trim(),
            adminEmail: _adminEmail.text.trim(),
            adminPassword: _adminPassword.text,
          );
      navigator.pop(tenant);
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = _selected;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Tenants',
        title: 'Promote from client',
        leading: selected == null
            ? null
            : InkActionButton(
                icon: Icons.arrow_back,
                tooltip: 'Choose a different client',
                onPressed: _backToSearch,
              ),
      ),
      body: selected == null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Search for the client to spin out into their own '
                    'independent, white-label tenant. Nothing about their '
                    'existing account moves.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      hintText: 'Name, email, phone or TIN',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.all(Spacing.lg),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_search.text.trim().length >= 2 && _results.isEmpty)
                    const StateMessage(
                      icon: Icons.search_off_outlined,
                      title: 'No clients found',
                      message: 'Try a different spelling, or fewer words.',
                    )
                  else
                    Expanded(
                      child: CrmCardList(
                        children: [
                          for (final client in _results)
                            ListTile(
                              title: Text(
                                client.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: CrmMetaLine(
                                [
                                  client.tenantName ?? 'Unknown tenant',
                                  ?client.email,
                                  ?client.phone,
                                ].join(' · '),
                              ),
                              onTap: () => _pick(client),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xl,
              ),
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: Spacing.md),
                ],
                Text(
                  'Promoting ${selected.name} (currently a client of '
                  '${selected.tenantName ?? 'an unknown tenant'}) — this '
                  'creates a brand-new, separate tenant; nothing about their '
                  'existing account moves.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                CrmField(
                  label: 'Company name',
                  child: TextField(
                    controller: _name,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Company email',
                  child: TextField(
                    controller: _email,
                    enabled: !_saving,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Phone',
                  child: TextField(
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Address',
                  child: TextField(
                    controller: _address,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Tax ID / TIN',
                  child: TextField(
                    controller: _taxId,
                    enabled: !_saving,
                    autocorrect: false,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Currency',
                  child: TextField(
                    controller: _currency,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'e.g. TZS'),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Text('Their admin account', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Admin name',
                  child: TextField(
                    controller: _adminName,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Admin email',
                  child: TextField(
                    controller: _adminEmail,
                    enabled: !_saving,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Admin password',
                  child: TextField(
                    controller: _adminPassword,
                    enabled: !_saving,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: 'Min. 8 characters',
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                PrimaryButton(
                  label: _saving ? 'Promoting…' : 'Promote to tenant',
                  busy: _saving,
                  icon: Icons.arrow_upward_outlined,
                  onPressed: _saving ? null : _submit,
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// A tenant's permission grants — `GET`/`PUT /admin/tenants/{id}/permissions`,
// the web's `TenantProfile.tsx`. Unchecking a permission also strips it from
// any of the tenant's own roles that had it (server-side, in
// `TenantPermissionController::updateTenantPermissions`).
// ---------------------------------------------------------------------------

class _TenantPermissionsScreen extends ConsumerStatefulWidget {
  const _TenantPermissionsScreen({
    required this.tenantId,
    required this.tenantName,
  });

  final String tenantId;
  final String tenantName;

  @override
  ConsumerState<_TenantPermissionsScreen> createState() =>
      _TenantPermissionsScreenState();
}

class _TenantPermissionsScreenState
    extends ConsumerState<_TenantPermissionsScreen> {
  List<PermissionInfo> _catalogue = const [];
  final Set<String> _enabled = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
      final service = ref.read(platformServiceProvider);
      final catalogue = await service.permissions();
      final ids = await service.tenantPermissionIds(widget.tenantId);
      if (!mounted) return;
      setState(() {
        _catalogue = catalogue;
        _enabled
          ..clear()
          ..addAll(ids);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final message = await ref
          .read(platformServiceProvider)
          .updateTenantPermissions(widget.tenantId, _enabled.toList());
      ref.invalidate(platformTenantProvider(widget.tenantId));
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Tenant permissions updated.')),
      );
      navigator.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final grouped = <String, List<PermissionInfo>>{};
    for (final p in _catalogue) {
      grouped.putIfAbsent(p.displayGroup, () => []).add(p);
    }

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: widget.tenantName,
        title: 'Permission grants',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xl,
              ),
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: Spacing.md),
                ],
                Text(
                  'What this tenant may use across the product. Unchecking a '
                  'permission also strips it from any of their roles that '
                  'had it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                for (final group in grouped.entries) ...[
                  SectionHeader(_titleCase(group.key.replaceAll('_', ' '))),
                  const SizedBox(height: Spacing.sm),
                  CrmCardList(
                    children: [
                      for (final perm in group.value)
                        CheckboxListTile(
                          value: _enabled.contains(perm.id),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          title: Text(
                            perm.displayLabel,
                            style: theme.textTheme.titleSmall,
                          ),
                          onChanged: perm.id.isEmpty || _saving
                              ? null
                              : (checked) => setState(() {
                                  if (checked ?? false) {
                                    _enabled.add(perm.id);
                                  } else {
                                    _enabled.remove(perm.id);
                                  }
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: Spacing.lg),
                ],
                PrimaryButton(
                  label: _saving ? 'Saving…' : 'Save permissions',
                  busy: _saving,
                  icon: Icons.save_outlined,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private building blocks (candidates for mobilling_ui)
// ---------------------------------------------------------------------------

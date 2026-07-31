import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmDetailRow;
import 'admin_providers.dart';

// ---------------------------------------------------------------------------
// Subscription — the tenant's own MoBilling plan
// ---------------------------------------------------------------------------

/// The tenant's plan with MoBilling.
///
/// Not to be confused with client subscriptions — money flows the other way
/// here. Checkout hands off to the payment gateway in a browser, same as the
/// client app's invoice payment.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(currentSubscriptionProvider);
    final history = ref.watch(subscriptionHistoryProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: CrmAsyncView(
        value: subscription,
        errorTitle: 'Could not load your subscription',
        onRetry: () => ref.invalidate(currentSubscriptionProvider),
        builder: (sub) => RefreshIndicator(
          onRefresh: () => ref.refresh(currentSubscriptionProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                            child: Text(sub.planName ?? 'No active plan',
                                style: theme.textTheme.titleMedium),
                          ),
                          StatusChip(sub.chipStatus, dense: true),
                        ],
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        sub.isExpired
                            ? 'Expired ${-sub.daysRemaining} days ago'
                            : '${sub.daysRemaining} days remaining',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: sub.isExpired
                              ? status.overdue
                              : sub.expiringSoon
                                  ? status.attention
                                  : null,
                        ),
                      ),
                      if (sub.planPrice != null)
                        Text(
                          '${Formatting.currency(sub.planPrice)}'
                          '${sub.billingCycle == null ? '' : ' / ${sub.billingCycle!.replaceAll('_', ' ')}'}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      const SizedBox(height: Spacing.sm),
                      if (sub.isTrial && sub.trialEndsAt != null)
                        CrmDetailRow(
                            'Trial ends', Formatting.date(sub.trialEndsAt)),
                      if (sub.endsAt != null)
                        CrmDetailRow('Renews', Formatting.date(sub.endsAt)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.icon(
                icon: const Icon(Icons.upgrade_outlined, size: 18),
                label: Text(sub.isExpired ? 'Renew now' : 'Change plan'),
                onPressed: () => _choosePlan(context, ref),
              ),
              const SizedBox(height: Spacing.lg),
              Text('Payment history', style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              history.maybeWhen(
                data: (entries) => entries.isEmpty
                    ? Text('No payments yet.',
                        style: theme.textTheme.bodySmall)
                    : Card(
                        child: Column(
                          children: [
                            for (final (i, entry) in entries.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                dense: true,
                                title: Text(entry.planName ?? 'Subscription'),
                                subtitle: Text(
                                  [
                                    if (entry.paidAt != null)
                                      Formatting.date(entry.paidAt),
                                    if (entry.startsAt != null &&
                                        entry.endsAt != null)
                                      '${Formatting.date(entry.startsAt)} – ${Formatting.date(entry.endsAt)}',
                                  ].join(' · '),
                                  style: theme.textTheme.bodySmall,
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(Formatting.currency(entry.amount),
                                        style: theme.textTheme.labelLarge),
                                    StatusChip(entry.status, dense: true),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choosePlan(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final plans = await ref.read(plansProvider.future);
    if (!context.mounted) return;

    final chosen = await showModalBottomSheet<SubscriptionPlan>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Text('Choose a plan',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final plan in plans)
              ListTile(
                title: Text(plan.name),
                subtitle: Text([
                  Formatting.currency(plan.price),
                  if (plan.billingCycle != null)
                    plan.billingCycle!.replaceAll('_', ' '),
                ].join(' / ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(plan),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;

    try {
      final url =
          await ref.read(adminServiceProvider).checkoutSubscription(chosen.id);
      if (url == null || url.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not start checkout.')));
        return;
      }
      // Hosted gateway page; the webhook settles it server-side.
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      ref.invalidate(currentSubscriptionProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ---------------------------------------------------------------------------
// Automation
// ---------------------------------------------------------------------------

/// What the scheduled jobs did, and whether any of them failed.
class AutomationScreen extends ConsumerWidget {
  const AutomationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(automationSummaryProvider(null));
    final logs = ref.watch(cronLogsProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Automation')),
      body: CrmAsyncView(
        value: summary,
        errorTitle: 'Could not load automation',
        onRetry: () => ref.invalidate(automationSummaryProvider(null)),
        builder: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(cronLogsProvider);
            ref.invalidate(automationSummaryProvider(null));
            await ref.read(automationSummaryProvider(null).future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (data.failedCommunications > 0)
                Container(
                  padding: const EdgeInsets.all(Spacing.md),
                  margin: const EdgeInsets.only(bottom: Spacing.md),
                  decoration: BoxDecoration(
                    color: status.overdue.withValues(alpha: 0.12),
                    borderRadius: Radii.card,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: status.overdue),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          '${data.failedCommunications} message${data.failedCommunications == 1 ? '' : 's'} failed to send',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Spacing.sm,
                crossAxisSpacing: Spacing.sm,
                childAspectRatio: 1.9,
                children: [
                  StatTile(
                      label: 'Invoices created',
                      value: '${data.invoicesCreated}'),
                  StatTile(
                      label: 'Reminders sent',
                      value: '${data.remindersSent}'),
                  StatTile(
                      label: 'Bills generated',
                      value: '${data.billsGenerated}'),
                  StatTile(
                      label: 'Subs expired',
                      value: '${data.subscriptionsExpired}',
                      emphasis: data.subscriptionsExpired > 0
                          ? status.attention
                          : null),
                  StatTile(label: 'Emails', value: '${data.emailsSent}'),
                  StatTile(label: 'SMS', value: '${data.smsSent}'),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              Text('Recent job runs', style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              logs.maybeWhen(
                data: (entries) => entries.isEmpty
                    ? Text('No runs recorded.',
                        style: theme.textTheme.bodySmall)
                    : Card(
                        child: Column(
                          children: [
                            for (final (i, entry)
                                in entries.take(30).indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  entry.failed
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline,
                                  size: 20,
                                  color: entry.failed
                                      ? status.overdue
                                      : status.settled,
                                ),
                                title: Text(entry.job),
                                subtitle: Text(
                                  [
                                    if (entry.ranAt != null)
                                      Formatting.dateTime(entry.ranAt),
                                    if (entry.durationMs != null)
                                      '${entry.durationMs}ms',
                                    if (entry.message != null) entry.message!,
                                  ].join(' · '),
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team
// ---------------------------------------------------------------------------

class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
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
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search name or email',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) => ref.read(adminServiceProvider).users(
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    page: page,
                  ),
              itemBuilder: (context, user) {
                final isSelf = user.id == me?.id;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(user.name.isEmpty
                          ? '?'
                          : user.name[0].toUpperCase()),
                    ),
                    title: Text(user.name + (isSelf ? ' (you)' : '')),
                    subtitle: Text(
                      [
                        user.email ?? '',
                        user.roleName ?? 'no role',
                        if (!user.isActive) 'deactivated',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: isSelf
                        ? null
                        : IconButton(
                            icon: Icon(
                              user.isActive
                                  ? Icons.toggle_on
                                  : Icons.toggle_off_outlined,
                              color: user.isActive
                                  ? context.statusColors.settled
                                  : null,
                            ),
                            tooltip: user.isActive
                                ? 'Deactivate'
                                : 'Reactivate',
                            onPressed: () => _toggle(user),
                          ),
                  ),
                );
              },
              emptyIcon: Icons.groups_outlined,
              emptyTitle: 'No staff accounts',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(StaffUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminServiceProvider).toggleUserActive(user.id);
      _listKey.currentState?.reload();
      messenger.showSnackBar(SnackBar(
          content: Text(user.isActive
              ? '${user.name} deactivated.'
              : '${user.name} reactivated.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ---------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------

/// Roles and what each one grants.
///
/// The web renders a wide permission matrix; on a phone that becomes a role
/// list drilling into a grouped checklist, which is the same information in a
/// shape a thumb can actually use.
class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(rolesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Roles')),
      body: CrmAsyncView(
        value: roles,
        errorTitle: 'Could not load roles',
        onRetry: () => ref.invalidate(rolesProvider),
        builder: (items) => ListView.separated(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: items.length,
          separatorBuilder: (context, index) =>
              const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) {
            final role = items[index];
            return Card(
              child: ListTile(
                title: Text(role.name),
                subtitle: Text(
                  [
                    '${role.usersCount} user${role.usersCount == 1 ? '' : 's'}',
                    '${role.permissionNames.length} permission${role.permissionNames.length == 1 ? '' : 's'}',
                    if (role.isSystem) 'system role',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  shape:
                      const RoundedRectangleBorder(borderRadius: Radii.sheet),
                  builder: (_) => _RolePermissionsSheet(role: role),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RolePermissionsSheet extends ConsumerWidget {
  const _RolePermissionsSheet({required this.role});

  final StaffRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final granted = role.permissionNames.toSet();

    // Group by the permission name's prefix so the list is scannable.
    final grouped = <String, List<String>>{};
    for (final name in role.permissionNames) {
      final group = name.contains('.') ? name.split('.').first : 'general';
      grouped.putIfAbsent(group, () => []).add(name);
    }
    final groups = grouped.keys.toList()..sort();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              children: [
                Text(role.name, style: theme.textTheme.titleLarge),
                Text(
                  '${granted.length} permission${granted.length == 1 ? '' : 's'}'
                  '${role.isSystem ? ' · system role' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                for (final group in groups) ...[
                  Text(group.replaceAll('_', ' '),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: Spacing.xs),
                  Wrap(
                    spacing: Spacing.xs,
                    runSpacing: Spacing.xs,
                    children: [
                      for (final name in grouped[group]!)
                        Chip(
                          label: Text(
                            name.split('.').last.replaceAll('_', ' '),
                            style: theme.textTheme.labelSmall,
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Text(
              // Editing a permission matrix on a phone is worse than not
              // offering it — say so rather than shipping a bad editor.
              'Edit role permissions from the web app.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/// Company profile and bank accounts — the details that print on invoices.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    final banks = ref.watch(bankAccountsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: CrmAsyncView(
        value: company,
        errorTitle: 'Could not load settings',
        onRetry: () => ref.invalidate(companySettingsProvider),
        builder: (settings) => ListView(
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
                          child: Text('Company',
                              style: theme.textTheme.titleSmall),
                        ),
                        TextButton(
                          onPressed: () => _editCompany(context, ref, settings),
                          child: const Text('Edit'),
                        ),
                      ],
                    ),
                    CrmDetailRow('Name', settings.name),
                    if (settings.email != null)
                      CrmDetailRow('Email', settings.email!),
                    if (settings.phone != null)
                      CrmDetailRow('Phone', settings.phone!),
                    if (settings.address != null)
                      CrmDetailRow('Address', settings.address!),
                    if (settings.taxId != null)
                      CrmDetailRow('TIN', settings.taxId!),
                    if (settings.currency != null)
                      CrmDetailRow('Currency', settings.currency!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text('Bank accounts', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            banks.maybeWhen(
              data: (accounts) => accounts.isEmpty
                  ? Text('None configured.', style: theme.textTheme.bodySmall)
                  : Card(
                      child: Column(
                        children: [
                          for (final (i, account) in accounts.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: Text(account.bankName),
                              subtitle: Text(
                                [
                                  account.accountName ?? '',
                                  account.accountNumber ?? '',
                                  account.branch ?? '',
                                ].where((s) => s.isNotEmpty).join(' · '),
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: account.isActive
                                  ? null
                                  : const StatusChip('draft', dense: true),
                            ),
                          ],
                        ],
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Email, SMS, templates, reminders and branding are configured '
              'in the web app.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _editCompany(
      BuildContext context, WidgetRef ref, CompanySettings current) async {
    final name = TextEditingController(text: current.name);
    final email = TextEditingController(text: current.email ?? '');
    final phone = TextEditingController(text: current.phone ?? '');
    final address = TextEditingController(text: current.address ?? '');
    final taxId = TextEditingController(text: current.taxId ?? '');
    final messenger = ScaffoldMessenger.of(context);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: Spacing.lg,
          right: Spacing.lg,
          top: Spacing.lg,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + Spacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Company details',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: Spacing.md),
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: Spacing.md),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: Spacing.md),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: Spacing.md),
              TextField(
                  controller: address,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Address')),
              const SizedBox(height: Spacing.md),
              TextField(
                  controller: taxId,
                  decoration: const InputDecoration(labelText: 'TIN')),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;

    try {
      await ref.read(adminServiceProvider).updateCompany(
            name: name.text.trim(),
            email: email.text.trim().isEmpty ? null : email.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            address: address.text.trim().isEmpty ? null : address.text.trim(),
            taxId: taxId.text.trim().isEmpty ? null : taxId.text.trim(),
          );
      ref.invalidate(companySettingsProvider);
      messenger
          .showSnackBar(const SnackBar(content: Text('Company updated.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

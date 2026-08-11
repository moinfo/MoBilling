import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmDetailRow;
import 'platform_providers.dart';
import 'platform_shell.dart';

// ---------------------------------------------------------------------------
// Subscription plans
// ---------------------------------------------------------------------------

class PlatformPlansScreen extends ConsumerWidget {
  const PlatformPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return PlatformListScaffold<PlatformPlan>(
      title: 'Subscription plans',
      value: ref.watch(platformPlansProvider),
      onRetry: () => ref.invalidate(platformPlansProvider),
      emptyIcon: Icons.card_membership_outlined,
      emptyTitle: 'No plans configured',
      itemBuilder: (context, plan) => Card(
        child: ListTile(
          title: Text(plan.name),
          subtitle: Text(
            [
              Formatting.currency(plan.price),
              if (plan.billingCycle != null)
                plan.billingCycle!.replaceAll('_', ' '),
              if (plan.durationDays != null) '${plan.durationDays} days',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          trailing: plan.isActive
              ? null
              : const StatusChip('draft', dense: true),
        ),
      ),
      footnote: 'Plan pricing is edited in the web admin.',
    );
  }
}

// ---------------------------------------------------------------------------
// Currencies
// ---------------------------------------------------------------------------

class CurrenciesScreen extends ConsumerWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return PlatformListScaffold<PlatformCurrency>(
      title: 'Currencies',
      value: ref.watch(currenciesProvider),
      onRetry: () => ref.invalidate(currenciesProvider),
      emptyIcon: Icons.currency_exchange_outlined,
      emptyTitle: 'No currencies configured',
      itemBuilder: (context, currency) => Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Text(currency.symbol ?? currency.code.substring(0, 1),
                style: theme.textTheme.labelLarge),
          ),
          title: Text(currency.code),
          subtitle: currency.name == null
              ? null
              : Text(currency.name!, style: theme.textTheme.bodySmall),
          trailing: currency.isActive
              ? null
              : const StatusChip('draft', dense: true),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SMS packages
// ---------------------------------------------------------------------------

class SmsPackagesScreen extends ConsumerWidget {
  const SmsPackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return PlatformListScaffold<SmsPackage>(
      title: 'SMS packages',
      value: ref.watch(smsPackagesProvider),
      onRetry: () => ref.invalidate(smsPackagesProvider),
      emptyIcon: Icons.sell_outlined,
      emptyTitle: 'No packages configured',
      itemBuilder: (context, package) => Card(
        child: ListTile(
          title: Text(package.name),
          subtitle: Text(
            // Unit price is the number that actually decides value, and the
            // API doesn't send it — so it's derived here.
            '${package.smsCount} messages · '
            '${Formatting.currency(package.unitPrice)} each',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Money(package.price),
              if (!package.isActive) const StatusChip('draft', dense: true),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SMS purchases
// ---------------------------------------------------------------------------

class SmsPurchasesScreen extends ConsumerStatefulWidget {
  const SmsPurchasesScreen({super.key});

  @override
  ConsumerState<SmsPurchasesScreen> createState() =>
      _SmsPurchasesScreenState();
}

class _SmsPurchasesScreenState extends ConsumerState<SmsPurchasesScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('pending', 'Pending'),
    ('completed', 'Completed'),
    ('failed', 'Failed'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('SMS purchases')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.sm),
              itemCount: _filters.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: Spacing.sm),
              itemBuilder: (context, index) {
                final (value, label) = _filters[index];
                return FilterChip(
                  label: Text(label),
                  selected: _status == value,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _status = value);
                    _listKey.currentState?.reload();
                  },
                );
              },
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) => ref
                  .read(platformServiceProvider)
                  .smsPurchases(status: _status, page: page),
              itemBuilder: (context, purchase) => Card(
                child: ListTile(
                  title: Text(purchase.tenantName ?? 'Purchase'),
                  subtitle: Text(
                    [
                      '${purchase.smsQuantity} messages',
                      if (purchase.userName != null) purchase.userName!,
                      if (purchase.createdAt != null)
                        Formatting.dateTime(purchase.createdAt),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Money(purchase.totalAmount),
                      StatusChip(
                          purchase.status == 'completed'
                              ? 'paid'
                              : purchase.status,
                          dense: true),
                    ],
                  ),
                ),
              ),
              emptyIcon: Icons.receipt_long_outlined,
              emptyTitle: 'No purchases',
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Permissions & role templates
// ---------------------------------------------------------------------------

/// The permission catalogue every tenant role is assembled from — read-only,
/// since permissions are defined in code, not data.
class PlatformPermissionsScreen extends ConsumerWidget {
  const PlatformPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(platformPermissionsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: CrmAsyncView(
        value: permissions,
        errorTitle: 'Could not load permissions',
        onRetry: () => ref.invalidate(platformPermissionsProvider),
        builder: (items) {
          final grouped = <String, List<PermissionInfo>>{};
          for (final p in items) {
            grouped.putIfAbsent(p.displayGroup, () => []).add(p);
          }
          final groups = grouped.keys.toList()..sort();

          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Text('${items.length} permissions across ${groups.length} areas',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: Spacing.md),
              for (final group in groups)
                Card(
                  margin: const EdgeInsets.only(bottom: Spacing.sm),
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(group.replaceAll('_', ' ')),
                    subtitle: Text('${grouped[group]!.length} permissions',
                        style: theme.textTheme.bodySmall),
                    childrenPadding: const EdgeInsets.fromLTRB(
                        Spacing.md, 0, Spacing.md, Spacing.sm),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: Spacing.xs,
                        runSpacing: Spacing.xs,
                        children: [
                          for (final p in grouped[group]!)
                            Chip(
                              label: Text(p.displayLabel,
                                  style: theme.textTheme.labelSmall),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class RoleTemplatesScreen extends ConsumerWidget {
  const RoleTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return PlatformListScaffold<StaffRole>(
      title: 'Role templates',
      value: ref.watch(roleTemplatesProvider),
      onRetry: () => ref.invalidate(roleTemplatesProvider),
      emptyIcon: Icons.shield_outlined,
      emptyTitle: 'No role templates',
      itemBuilder: (context, role) => Card(
        child: ListTile(
          title: Text(role.name),
          subtitle: Text(
            '${role.permissionNames.length} permission${role.permissionNames.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
      footnote: 'These are the roles a newly created tenant starts with.',
    );
  }
}

// ---------------------------------------------------------------------------
// Platform settings
// ---------------------------------------------------------------------------

class PlatformSettingsScreen extends ConsumerWidget {
  const PlatformSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(platformSettingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Platform settings')),
      body: CrmAsyncView(
        value: settings,
        errorTitle: 'Could not load platform settings',
        onRetry: () => ref.invalidate(platformSettingsProvider),
        builder: (s) {
          final keys = s.values.keys.toList()..sort();
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final key in keys)
                        CrmDetailRow(
                          key.replaceAll('_', ' '),
                          // Never print a secret, even to a super admin —
                          // shoulder-surfing on a phone is a real risk.
                          _isSecret(key) ? '••••••••' : s[key] ?? '',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Text(
                'Platform settings are edited in the web admin.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  static bool _isSecret(String key) {
    final k = key.toLowerCase();
    return k.contains('secret') ||
        k.contains('password') ||
        k.contains('key') ||
        k.contains('token');
  }
}

// ---------------------------------------------------------------------------
// Per-tenant email / SMS / templates
// ---------------------------------------------------------------------------

class TenantEmailSettingsScreen extends ConsumerWidget {
  const TenantEmailSettingsScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(tenantEmailSettingsProvider(tenantId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Email settings')),
      body: CrmAsyncView(
        value: settings,
        errorTitle: 'Could not load email settings',
        onRetry: () => ref.invalidate(tenantEmailSettingsProvider(tenantId)),
        builder: (s) => ListView(
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
                          child: Text('SMTP',
                              style: theme.textTheme.titleSmall),
                        ),
                        StatusChip(s.emailEnabled ? 'active' : 'draft',
                            dense: true),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    if (s.fromName != null)
                      CrmDetailRow('From name', s.fromName!),
                    if (s.fromAddress != null)
                      CrmDetailRow('From address', s.fromAddress!),
                    if (s.host != null) CrmDetailRow('Host', s.host!),
                    if (s.port != null) CrmDetailRow('Port', '${s.port}'),
                    if (s.username != null)
                      CrmDetailRow('Username', s.username!),
                    if (s.encryption != null)
                      CrmDetailRow('Encryption', s.encryption!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            // Sends a real message — the only honest verification.
            FilledButton.icon(
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Send test email'),
              onPressed: () => _test(context, ref),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'SMTP credentials are edited in the web admin.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _test(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Sending…')));
    try {
      final message =
          await ref.read(platformServiceProvider).testTenantEmail(tenantId);
      messenger.showSnackBar(
          SnackBar(content: Text(message ?? 'Test email sent.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class TenantSmsSettingsScreen extends ConsumerWidget {
  const TenantSmsSettingsScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(tenantSmsSettingsProvider(tenantId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('SMS settings')),
      body: CrmAsyncView(
        value: settings,
        errorTitle: 'Could not load SMS settings',
        onRetry: () => ref.invalidate(tenantSmsSettingsProvider(tenantId)),
        builder: (s) => ListView(
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
                          child:
                              Text('SMS', style: theme.textTheme.titleSmall),
                        ),
                        StatusChip(s.smsEnabled ? 'active' : 'draft',
                            dense: true),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    CrmDetailRow('Balance', '${s.smsBalance} messages'),
                    if (s.senderId != null)
                      CrmDetailRow('Sender ID', s.senderId!),
                    CrmDetailRow(
                        'Reminders', s.reminderSmsEnabled ? 'On' : 'Off'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Recharge and deduct from the tenant screen.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class TenantTemplatesScreen extends ConsumerWidget {
  const TenantTemplatesScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return PlatformListScaffold<TenantTemplate>(
      title: 'Email templates',
      value: ref.watch(tenantTemplatesProvider(tenantId)),
      onRetry: () => ref.invalidate(tenantTemplatesProvider(tenantId)),
      emptyIcon: Icons.description_outlined,
      emptyTitle: 'No template overrides',
      itemBuilder: (context, template) => Card(
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(template.label ?? template.key.replaceAll('_', ' ')),
          subtitle: template.subject == null
              ? null
              : Text(template.subject!, style: theme.textTheme.bodySmall),
          childrenPadding:
              const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.md),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(htmlToPlainText(template.body),
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      footnote: 'Templates are edited in the web admin.',
    );
  }
}

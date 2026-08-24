import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmDetailRow,
        CrmMetaLine,
        CrmStatusLine,
        FilterStrip;
import 'platform_providers.dart';
import 'platform_shell.dart';
import 'role_template_editor_sheet.dart';

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
              Flexible(
                child: CrmMetaLine(
                  [
                    if (plan.billingCycle != null)
                      plan.billingCycle!.replaceAll('_', ' '),
                    if (plan.durationDays != null) '${plan.durationDays} days',
                  ].join(' · '),
                ),
              ),
            ],
          ),
        ),
        trailing: Money(plan.price),
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
      itemBuilder: (context, currency) => ListTile(
        dense: true,
        // The code is the name here — set as a label, not as a sentence.
        title: Text(
          currency.code.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: currency.name == null && currency.isActive
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    if (!currency.isActive) ...[
                      const StatusChip('draft', dense: true),
                      const SizedBox(width: Spacing.sm),
                    ],
                    if (currency.name != null)
                      Flexible(
                        child: Text(
                          currency.name!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        trailing: currency.symbol == null
            ? null
            : Text(currency.symbol!, style: theme.textTheme.titleMedium),
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
      itemBuilder: (context, package) => ListTile(
        title: Text(package.name, style: theme.textTheme.titleSmall),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              if (!package.isActive) ...[
                const StatusChip('draft', dense: true),
                const SizedBox(width: Spacing.sm),
              ],
              Flexible(
                child: CrmMetaLine(
                  '${Formatting.integer(package.smsCount)} messages',
                ),
              ),
            ],
          ),
        ),
        // Unit price is the number that actually decides value, and the API
        // doesn't send it — so it's derived here, under the pack price.
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Money(package.price),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Money(
                  package.unitPrice,
                  scale: MoneyScale.dense,
                  showCode: false,
                ),
                const SizedBox(width: Spacing.xs),
                const CrmMetaLine('each'),
              ],
            ),
          ],
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
  ConsumerState<SmsPurchasesScreen> createState() => _SmsPurchasesScreenState();
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
      appBar: const ShellTopBar(eyebrow: 'Platform', title: 'SMS purchases'),
      body: Column(
        children: [
          FilterStrip(
            options: _filters,
            selected: _status,
            onSelect: (value) {
              setState(() => _status = value);
              _listKey.currentState?.reload();
            },
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                Spacing.xl,
              ),
              fetch: (page) => ref
                  .read(platformServiceProvider)
                  .smsPurchases(status: _status, page: page),
              itemBuilder: (context, purchase) => Card(
                child: ListTile(
                  title: Text(
                    purchase.tenantName ?? 'Purchase',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: CrmStatusLine(
                      // 'completed' is a settled payment; the shared chip
                      // reads 'paid' for that.
                      status: purchase.status == 'completed'
                          ? 'paid'
                          : purchase.status,
                      meta: [
                        '${Formatting.integer(purchase.smsQuantity)} messages',
                        if (purchase.userName != null) purchase.userName!,
                        if (purchase.createdAt != null)
                          Formatting.dateTime(purchase.createdAt),
                      ].join(' · '),
                    ),
                  ),
                  trailing: Money(purchase.totalAmount),
                ),
              ),
              emptyIcon: Icons.receipt_long_outlined,
              emptyTitle: 'No purchases',
              emptyMessage: 'Nothing matches this filter.',
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
      appBar: const ShellTopBar(eyebrow: 'Platform', title: 'Permissions'),
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
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.xl,
            ),
            children: [
              SectionHeader(
                'The catalogue',
                trailing: CrmMetaLine(
                  '${Formatting.integer(items.length)} across '
                  '${Formatting.integer(groups.length)} areas',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              CrmCardList(
                children: [
                  for (final group in groups)
                    ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(
                        group.replaceAll('_', ' '),
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: CrmMetaLine(
                          '${Formatting.integer(grouped[group]!.length)} '
                          'permissions',
                        ),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(
                        Spacing.md,
                        0,
                        Spacing.md,
                        Spacing.md,
                      ),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: Spacing.xs,
                          runSpacing: Spacing.xs,
                          children: [
                            for (final p in grouped[group]!)
                              Chip(
                                label: Text(p.displayLabel),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                      ],
                    ),
                ],
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

    return PlatformListScaffold<RoleTemplate>(
      title: 'Role templates',
      value: ref.watch(roleTemplatesProvider),
      onRetry: () => ref.invalidate(roleTemplatesProvider),
      emptyIcon: Icons.shield_outlined,
      emptyTitle: 'No role templates',
      itemBuilder: (context, role) => ListTile(
        title: Text(role.label, style: theme.textTheme.titleSmall),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: CrmMetaLine(
            '${Formatting.integer(role.permissionsCount)} / '
            '${Formatting.integer(role.totalPermissions)} permissions'
            '${role.tenantsCount == null ? '' : ' · ${Formatting.integer(role.tenantsCount!)} tenants'}',
          ),
        ),
        trailing: role.editable
            ? Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.outline,
              )
            : Icon(
                Icons.lock_outline,
                size: 16,
                color: theme.colorScheme.outline,
              ),
        onTap: !role.editable
            ? null
            : () => showRoleTemplateEditor(context, role),
      ),
      footnote:
          'These are the roles a newly created tenant starts with. Editing '
          'one applies the change to every existing tenant of that type too.',
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
      appBar: const ShellTopBar(
        eyebrow: 'Platform',
        title: 'Platform settings',
      ),
      body: CrmAsyncView(
        value: settings,
        errorTitle: 'Could not load platform settings',
        onRetry: () => ref.invalidate(platformSettingsProvider),
        builder: (s) {
          final keys = s.values.keys.toList()..sort();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.xl,
            ),
            children: [
              const SectionHeader('Configuration'),
              const SizedBox(height: Spacing.sm),
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
              const SizedBox(height: Spacing.lg),
              Text(
                'Platform settings are edited in the web admin.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
      appBar: const ShellTopBar(eyebrow: 'Tenant', title: 'Email settings'),
      body: CrmAsyncView(
        value: settings,
        errorTitle: 'Could not load email settings',
        onRetry: () => ref.invalidate(tenantEmailSettingsProvider(tenantId)),
        builder: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.xl,
          ),
          children: [
            SectionHeader(
              'SMTP',
              trailing: StatusChip(
                s.emailEnabled ? 'active' : 'draft',
                dense: true,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
            const SizedBox(height: Spacing.lg),
            // Sends a real message — the only honest verification.
            PrimaryButton(
              label: 'Send test email',
              icon: Icons.send_outlined,
              onPressed: () => _test(context, ref),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'SMTP credentials are edited in the web admin.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
      final message = await ref
          .read(platformServiceProvider)
          .testTenantEmail(tenantId);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Test email sent.')),
      );
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
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Tenant', title: 'SMS settings'),
      body: CrmAsyncView(
        value: settings,
        errorTitle: 'Could not load SMS settings',
        onRetry: () => ref.invalidate(tenantSmsSettingsProvider(tenantId)),
        builder: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.xl,
          ),
          children: [
            // What everything else on this screen is about: how many messages
            // this tenant can still send.
            Reveal(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'SMS BALANCE',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          StatusChip(
                            s.smsEnabled ? 'active' : 'draft',
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            Formatting.integer(s.smsBalance),
                            style: Type.display(
                              MoneyScale.display.size,
                              color: scheme.onSurface,
                            ).copyWith(fontFeatures: Type.figures),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Text(
                            'messages',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Sending'),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.senderId != null)
                      CrmDetailRow('Sender ID', s.senderId!),
                    CrmDetailRow(
                      'Reminders',
                      s.reminderSmsEnabled ? 'On' : 'Off',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Recharge and deduct from the tenant screen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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
      eyebrow: 'Tenant',
      title: 'Email templates',
      value: ref.watch(tenantTemplatesProvider(tenantId)),
      onRetry: () => ref.invalidate(tenantTemplatesProvider(tenantId)),
      emptyIcon: Icons.description_outlined,
      emptyTitle: 'No template overrides',
      itemBuilder: (context, template) => ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          template.label ?? template.key.replaceAll('_', ' '),
          style: theme.textTheme.titleSmall,
        ),
        subtitle: template.subject == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  template.subject!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
        childrenPadding: const EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            htmlToPlainText(template.body),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      footnote: 'Templates are edited in the web admin.',
    );
  }
}

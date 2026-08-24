import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme_mode.dart';
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
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Account', title: 'Subscription'),
      body: CrmAsyncView(
        value: subscription,
        errorTitle: 'Could not load your subscription',
        onRetry: () => ref.invalidate(currentSubscriptionProvider),
        builder: (sub) => RefreshIndicator(
          onRefresh: () => ref.refresh(currentSubscriptionProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.xl,
            ),
            children: [
              // The days left are what this screen is about — an expiring
              // plan locks a whole company out — so they are the hero.
              Reveal(child: _PlanCard(sub: sub)),
              const SizedBox(height: Spacing.md),
              PrimaryButton(
                label: sub.isExpired ? 'Renew now' : 'Change plan',
                onPressed: () => _choosePlan(context, ref),
              ),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Payment history'),
              const SizedBox(height: Spacing.sm),
              history.maybeWhen(
                data: (entries) => entries.isEmpty
                    ? Text(
                        'No payments yet.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : CrmCardList(
                        children: [
                          for (final entry in entries)
                            ListTile(
                              dense: true,
                              title: Text(
                                entry.planName ?? 'Subscription',
                                style: theme.textTheme.titleSmall,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: CrmStatusLine(
                                  status: entry.status,
                                  meta: [
                                    if (entry.paidAt != null)
                                      Formatting.date(entry.paidAt),
                                    if (entry.startsAt != null &&
                                        entry.endsAt != null)
                                      '${Formatting.date(entry.startsAt)} – '
                                          '${Formatting.date(entry.endsAt)}',
                                  ].join(' · '),
                                ),
                              ),
                              trailing: Money(entry.amount),
                            ),
                        ],
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
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

    final chosen = await showCrmSheet<SubscriptionPlan>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return CrmSheet(
          eyebrow: 'Subscription',
          title: 'Choose a plan',
          children: [
            CrmCardList(
              children: [
                for (final plan in plans)
                  ListTile(
                    title: Text(plan.name, style: theme.textTheme.titleSmall),
                    subtitle: plan.billingCycle == null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: CrmMetaLine(
                              plan.billingCycle!.replaceAll('_', ' '),
                            ),
                          ),
                    trailing: Money(plan.price),
                    onTap: () => Navigator.of(sheetContext).pop(plan),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (chosen == null) return;

    try {
      final url = await ref
          .read(adminServiceProvider)
          .checkoutSubscription(chosen.id);
      if (url == null || url.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not start checkout.')),
        );
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

/// The plan, with the days left as the one figure on the screen. The card
/// takes a 6% wash of the status colour only when the answer is bad — a
/// healthy subscription is not news and should not be coloured like it is.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.sub});

  final TenantSubscription sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    final tone = sub.isExpired
        ? status.overdue
        : sub.expiringSoon
        ? status.attention
        : null;
    final days = sub.isExpired ? -sub.daysRemaining : sub.daysRemaining;

    return Card(
      color: tone == null
          ? null
          : Color.alphaBlend(tone.withValues(alpha: 0.06), scheme.surface),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sub.planName ?? 'No active plan',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                StatusChip(sub.chipStatus, dense: true),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              sub.isExpired ? 'EXPIRED' : 'DAYS REMAINING',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  Formatting.integer(days),
                  style: Type.display(
                    34,
                    color: tone ?? scheme.onSurface,
                  ).copyWith(fontFeatures: Type.figures),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  sub.isExpired
                      ? '${days == 1 ? 'day' : 'days'} ago'
                      : days == 1
                      ? 'day'
                      : 'days',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (sub.planPrice != null) ...[
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Money(sub.planPrice),
                  if (sub.billingCycle != null) ...[
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: CrmMetaLine(
                        sub.billingCycle!.replaceAll('_', ' '),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if ((sub.isTrial && sub.trialEndsAt != null) ||
                sub.endsAt != null) ...[
              const Divider(height: Spacing.lg),
              if (sub.isTrial && sub.trialEndsAt != null)
                CrmDetailRow('Trial ends', Formatting.date(sub.trialEndsAt)),
              if (sub.endsAt != null)
                CrmDetailRow('Renews', Formatting.date(sub.endsAt)),
            ],
          ],
        ),
      ),
    );
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
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Automation', title: 'Automation'),
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
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.xl,
            ),
            children: [
              // The one number worth interrupting someone for.
              if (data.failedCommunications > 0) ...[
                ErrorBanner(
                  message:
                      '${Formatting.integer(data.failedCommunications)} '
                      'message${data.failedCommunications == 1 ? '' : 's'} '
                      'failed to send',
                ),
                const SizedBox(height: Spacing.md),
              ],
              SectionHeader(
                'Billing',
                trailing: data.date.isEmpty
                    ? null
                    : CrmMetaLine(Formatting.date(data.date)),
              ),
              const SizedBox(height: Spacing.sm),
              StatRail(
                items: [
                  StatRailItem(
                    label: 'Invoices',
                    value: Formatting.integer(data.invoicesCreated),
                  ),
                  StatRailItem(
                    label: 'Reminders',
                    value: Formatting.integer(data.remindersSent),
                  ),
                  StatRailItem(
                    label: 'Bills',
                    value: Formatting.integer(data.billsGenerated),
                  ),
                  StatRailItem(
                    label: 'Expired',
                    value: Formatting.integer(data.subscriptionsExpired),
                    emphasis: data.subscriptionsExpired > 0
                        ? status.attention
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Messages'),
              const SizedBox(height: Spacing.sm),
              StatRail(
                items: [
                  StatRailItem(
                    label: 'Emails',
                    value: Formatting.integer(data.emailsSent),
                  ),
                  StatRailItem(
                    label: 'SMS',
                    value: Formatting.integer(data.smsSent),
                  ),
                  StatRailItem(
                    label: 'Failed',
                    value: Formatting.integer(data.failedCommunications),
                    emphasis: data.failedCommunications > 0
                        ? status.overdue
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Recent job runs'),
              const SizedBox(height: Spacing.sm),
              logs.maybeWhen(
                data: (entries) => entries.isEmpty
                    ? Text(
                        'No runs recorded.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : CrmCardList(
                        children: [
                          for (final entry in entries.take(30))
                            _JobRow(entry: entry),
                        ],
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One scheduled run: the job it was, a chip for how it ended, and the
/// duration as the row's trailing figure so the column reads down.
class _JobRow extends StatelessWidget {
  const _JobRow({required this.entry});

  final CronLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      dense: true,
      title: Text(
        entry.job,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CrmStatusLine(
              status: entry.failed ? 'failed' : 'completed',
              meta: entry.ranAt == null ? '' : Formatting.dateTime(entry.ranAt),
            ),
            if (entry.message != null && entry.message!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  entry.message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
      trailing: entry.durationMs == null
          ? null
          : Text(
              '${Formatting.integer(entry.durationMs)}ms',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
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
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Account',
        title: 'Team',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search name or email',
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
            .read(adminServiceProvider)
            .users(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        itemBuilder: (context, user) {
          final isSelf = user.id == me?.id;
          return Card(
            child: ListTile(
              title: Text(
                user.name + (isSelf ? ' (you)' : ''),
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: CrmStatusLine(
                  status: user.isActive ? 'active' : 'deactivated',
                  meta: [
                    user.email ?? '',
                    user.roleName ?? 'no role',
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
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
                      tooltip: user.isActive ? 'Deactivate' : 'Reactivate',
                      onPressed: () => _toggle(user),
                    ),
            ),
          );
        },
        emptyIcon: Icons.groups_outlined,
        emptyTitle: 'No staff accounts',
        emptyMessage: 'Nothing matches this search.',
      ),
    );
  }

  Future<void> _toggle(StaffUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminServiceProvider).toggleUserActive(user.id);
      _listKey.currentState?.reload();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            user.isActive
                ? '${user.name} deactivated.'
                : '${user.name} reactivated.',
          ),
        ),
      );
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
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Account', title: 'Roles'),
      body: CrmAsyncView(
        value: roles,
        errorTitle: 'Could not load roles',
        onRetry: () => ref.invalidate(rolesProvider),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.shield_outlined,
                title: 'No roles yet',
                message: 'Roles are created in the web app.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.xl,
                ),
                children: [
                  CrmCardList(
                    children: [
                      for (final role in items)
                        ListTile(
                          title: Text(
                            role.name,
                            style: theme.textTheme.titleSmall,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: CrmMetaLine(
                              [
                                '${role.usersCount} '
                                    'user${role.usersCount == 1 ? '' : 's'}',
                                if (role.isSystem) 'system role',
                              ].join(' · '),
                            ),
                          ),
                          // The permission count is the figure that separates
                          // one role from the next, so it holds the right
                          // edge like an amount would.
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                Formatting.integer(role.permissionNames.length),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: Spacing.xs),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: scheme.outline,
                              ),
                            ],
                          ),
                          onTap: () => showCrmSheet<void>(
                            context: context,
                            builder: (_) => _RolePermissionsSheet(role: role),
                          ),
                        ),
                    ],
                  ),
                ],
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
    final scheme = theme.colorScheme;
    final granted = role.permissionNames.toSet();

    // Group by the permission name's prefix so the list is scannable.
    final grouped = <String, List<String>>{};
    for (final name in role.permissionNames) {
      final group = name.contains('.') ? name.split('.').first : 'general';
      grouped.putIfAbsent(group, () => []).add(name);
    }
    final groups = grouped.keys.toList()..sort();

    return CrmSheet(
      eyebrow: 'Role',
      title: role.name,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.lg),
          child: Text(
            '${granted.length} permission${granted.length == 1 ? '' : 's'}'
            '${role.isSystem ? ' · system role' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final group in groups) ...[
          Text(
            group.replaceAll('_', ' ').toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              for (final name in grouped[group]!)
                Chip(
                  label: Text(name.split('.').last.replaceAll('_', ' ')),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
        ],
        const SizedBox(height: Spacing.sm),
        Text(
          // Editing a permission matrix on a phone is worse than not
          // offering it — say so rather than shipping a bad editor.
          'Edit role permissions from the web app.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
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
    final scheme = theme.colorScheme;

    // PUT /settings/company needs settings.company.
    final canEdit =
        ref.watch(sessionControllerProvider).session?.can('settings.company') ??
        false;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Account', title: 'Settings'),
      body: CrmAsyncView(
        value: company,
        errorTitle: 'Could not load settings',
        onRetry: () => ref.invalidate(companySettingsProvider),
        builder: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.xl,
          ),
          children: [
            // Device-level preference — the same control as the profile
            // sheet and the sign-in toggle, so the choice is reachable
            // wherever someone looks for it.
            const SectionHeader('Appearance'),
            const SizedBox(height: Spacing.sm),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: AppearanceControl(),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            SectionHeader(
              'Company',
              trailing: !canEdit
                  ? null
                  : TextButton(
                      onPressed: () => _editCompany(context, ref, settings),
                      child: const Text('Edit'),
                    ),
            ),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Bank accounts'),
            const SizedBox(height: Spacing.sm),
            banks.maybeWhen(
              data: (accounts) => accounts.isEmpty
                  ? Text(
                      'None configured.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : CrmCardList(
                      children: [
                        for (final account in accounts)
                          ListTile(
                            dense: true,
                            title: Text(
                              account.bankName,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: CrmMetaLine(
                                [
                                  account.accountName ?? '',
                                  account.accountNumber ?? '',
                                  account.branch ?? '',
                                ].where((s) => s.isNotEmpty).join(' · '),
                              ),
                            ),
                            trailing: account.isActive
                                ? null
                                : const StatusChip('draft', dense: true),
                          ),
                      ],
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Email, SMS, templates, reminders and branding are configured '
              'in the web app.',
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

  Future<void> _editCompany(
    BuildContext context,
    WidgetRef ref,
    CompanySettings current,
  ) async {
    final name = TextEditingController(text: current.name);
    final email = TextEditingController(text: current.email ?? '');
    final phone = TextEditingController(text: current.phone ?? '');
    final address = TextEditingController(text: current.address ?? '');
    final taxId = TextEditingController(text: current.taxId ?? '');
    final messenger = ScaffoldMessenger.of(context);

    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (sheetContext) => CrmSheet(
        eyebrow: 'Settings',
        title: 'Company details',
        children: [
          CrmField(
            label: 'Name',
            child: TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'The name that prints on invoices',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Email',
            child: TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'billing@company.co.tz',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Phone',
            child: TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Reachable number'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Address',
            child: TextField(
              controller: address,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Street, city'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'TIN',
            child: TextField(
              controller: taxId,
              decoration: const InputDecoration(hintText: 'Tax number'),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Save company',
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
        ],
      ),
    );
    if (saved != true) return;

    if (email.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('A company email is required.')),
      );
      return;
    }

    try {
      await ref
          .read(adminServiceProvider)
          .updateCompany(
            name: name.text.trim(),
            email: email.text.trim(),
            // Required by the API; not editable here — it is the billing
            // currency and changing it is a web/super-admin decision.
            currency: current.currency ?? Formatting.tenantCurrency,
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            address: address.text.trim().isEmpty ? null : address.text.trim(),
            taxId: taxId.text.trim().isEmpty ? null : taxId.text.trim(),
          );
      ref.invalidate(companySettingsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Company updated.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ---------------------------------------------------------------------------
// Private building blocks (candidates for mobilling_ui)
// ---------------------------------------------------------------------------

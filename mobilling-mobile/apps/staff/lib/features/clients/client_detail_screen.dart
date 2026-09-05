import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../../router.dart';
import '../billing_money/billing_money_providers.dart';
import '../common/paged_list.dart';
import '../common/pickers.dart' show ClientPickerSheet;
import '../crm/crm_providers.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmDetailRow,
        CrmField,
        CrmMetaLine,
        CrmSheet,
        CrmStatusLine,
        FilterStrip,
        RatingStars,
        showCrmSheet;
import '../documents/documents_tab.dart' show StaffInvoiceCard;
import 'client_form_screen.dart';
import 'client_providers.dart';

/// One client, as a profile rather than as a list of their invoices.
///
/// The subject of the screen is the person or company; the figure it is about
/// is what they owe. Everything else is a section under that — what they buy,
/// who else works there, what we have sent them — with invoices, quotes and
/// payments each kept on their own paged tab rather than folded into
/// Overview, since a busy client can outgrow what one screen shows at once.
///
/// Editing lives here now: the record, the staff notes, the wallet, the
/// additional contacts and portal access are all reachable without a
/// browser. So do merging and deleting a client, and signing in as their
/// portal account — each carries a blast radius (another record's history,
/// or the record itself), so the actions sheet gates every one of them on
/// its own permission and the confirmation in front of it says plainly what
/// is about to happen rather than leaning on a server-side safety net that,
/// for delete in particular, does not exist.
class ClientDetailScreen extends ConsumerStatefulWidget {
  const ClientDetailScreen({
    super.key,
    required this.clientId,
    this.clientName,
  });

  final String clientId;

  /// Passed when arriving from the clients list. Absent on a deep link — a
  /// push notification, a shared URL — in which case the profile names it.
  final String? clientName;

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen>
    with SingleTickerProviderStateMixin {
  // Payments is the one tab gated on a permission most billing roles do
  // hold but not all do (`payments_in.read`) — decided once at open time,
  // since permissions do not change under a screen that is already showing.
  late final bool _showPayments;
  late final List<String> _tabLabels;
  late final TabController _tabs;

  String get _clientId => widget.clientId;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider).session;
    _showPayments =
        session?.can(BillingMoneyPermissions.paymentsInRead) ?? false;
    _tabLabels = [
      'Overview',
      'Invoices',
      'Quotes',
      if (_showPayments) 'Payments',
      'People',
      'Activity',
    ];
    _tabs = TabController(length: _tabLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// The masthead's action button. Everything that writes to the client sits
  /// in one sheet rather than as a row of icons a thumb cannot hit.
  Future<void> _openActions(ClientProfile profile) async {
    final action = await showCrmSheet<String>(
      context: context,
      builder: (_) => _ActionsSheet(profile: profile),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'edit':
        await Navigator.of(context).push<StaffClient>(
          MaterialPageRoute(
            builder: (_) => ClientFormScreen(existing: profile.client),
          ),
        );
      case 'notes':
        await showCrmSheet<void>(
          context: context,
          builder: (_) => _NotesSheet(profile: profile),
        );
      case 'credit':
        await showCrmSheet<void>(
          context: context,
          builder: (_) => _AdjustCreditSheet(profile: profile),
        );
      case 'apply-credit':
        await showCrmSheet<void>(
          context: context,
          builder: (_) => _ApplyCreditSheet(profile: profile),
        );
      case 'reseller':
        await _makeReseller(profile);
      case 'portal-login':
        await _loginAsClient(profile);
      case 'merge':
        await _mergeClient(profile);
      case 'delete':
        await _deleteClient(profile);
    }
  }

  Future<void> _makeReseller(ClientProfile profile) async {
    final confirmed = await _confirm(
      context,
      title: 'Make ${profile.client.name} a reseller?',
      body:
          'This raises a Reseller Membership subscription and an annual fee '
          'invoice. They become a reseller once that invoice is paid, and '
          'stop being one if it lapses.',
      verb: 'Create invoice',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(staffServiceProvider)
          .makeClientReseller(profile.client.id);
      ref.invalidate(clientProfileProvider(_clientId));
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Reseller invoice created.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Mints a live portal session and swaps into it — the same
  /// swap-and-stash mechanism platform-admin tenant impersonation uses (see
  /// `_adoptImpersonation` in `features/platform/tenants_screens.dart`), just
  /// against the client-portal login endpoint instead of the tenant one.
  /// Unlike that endpoint, this one's response already carries
  /// `user_type: 'client'`, so the body needs no injection before
  /// `AuthSession.fromJson` reads it.
  Future<void> _loginAsClient(ClientProfile profile) async {
    final confirmed = await _confirm(
      context,
      title: "Sign in as ${profile.client.name}'s portal account?",
      body:
          'This swaps your session for their client-portal login. Open the '
          'account sheet (tap your avatar) and use "Back to …" to return.',
      verb: 'Sign in',
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final body = await ref
          .read(staffServiceProvider)
          .portalLoginAsClient(profile.client.id);
      final session = AuthSession.fromJson(body);
      await ref.read(sessionControllerProvider).impersonate(session);
    } on ApiException catch (e) {
      // Most likely "Client has no email address. Add an email first." —
      // shown verbatim rather than a generic failure.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The server enforces no guard of its own on this — no outstanding
  /// balance check, nothing — so the confirmation dialog is the only thing
  /// standing between a tap and a client record that is simply gone.
  Future<void> _deleteClient(ClientProfile profile) async {
    final client = profile.client;
    final confirmed = await _confirm(
      context,
      title: 'Delete ${client.name}?',
      body:
          'Type-to-confirm is skipped on a phone, so read this instead: '
          'deleting "${client.name}" removes the client record itself. '
          'Their invoices, subscriptions and history stay for audit '
          'purposes, but the client will no longer appear anywhere in the '
          'app. This cannot be undone.',
      verb: 'Delete client',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(staffServiceProvider)
          .deleteClient(client.id);
      if (!mounted) return;
      // Nothing left on this screen to show — back to the list, the way
      // every other "this record is gone" flow in the app already leaves.
      context.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? '${client.name} deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Picks the other client, picks a survivor, spells out what moves before
  /// asking, then shows exactly what did move — the confirmation is the
  /// safety net; the summary afterwards is the audit trail for whoever ran
  /// it, since [ClientMergeResult.movedCounts] would otherwise be silently
  /// trusted rather than seen.
  Future<void> _mergeClient(ClientProfile profile) async {
    final first = profile.client;
    final second = await ClientPickerSheet.show(context);
    if (second == null || !mounted) return;

    final keep = await _chooseMergeSurvivor(
      context,
      first: first,
      second: second,
    );
    if (keep == null || !mounted) return;

    final survivorName = keep == 'first' ? first.name : second.name;
    final absorbedName = keep == 'first' ? second.name : first.name;
    final confirmed = await _confirm(
      context,
      title: 'Merge into $survivorName?',
      body:
          'Everything belonging to "$absorbedName" — invoices, '
          'subscriptions, tickets, payments and more — is reassigned to '
          '$survivorName. "$absorbedName" is then gone for good. This '
          'cannot be undone.',
      verb: 'Merge clients',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(staffServiceProvider)
          .mergeClients(first.id, otherClientId: second.id, keep: keep);
      if (!mounted) return;
      await _showMergeSummary(context, result, survivorName: survivorName);
      if (!mounted) return;
      if (keep == 'first') {
        ref.invalidate(clientProfileProvider(first.id));
      } else {
        context.pushReplacement(Routes.clientPath(result.survivorId));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(clientProfileProvider(_clientId));
    final loaded = profile.valueOrNull;
    final title = loaded?.client.name ?? widget.clientName ?? 'Client';

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Clients',
        title: title,
        trailing: loaded == null
            ? null
            : InkActionButton(
                icon: Icons.bolt_outlined,
                tooltip: 'Actions',
                onPressed: () => _openActions(loaded),
              ),
        bottom: InkTabBar(
          controller: _tabs,
          isScrollable: _tabLabels.length > 3,
          tabs: _tabLabels,
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          CrmAsyncView(
            value: profile,
            errorTitle: 'Could not load this client',
            onRetry: () => ref.invalidate(clientProfileProvider(_clientId)),
            builder: (data) => _OverviewTab(profile: data),
          ),
          // The invoice list is its own paged read against /documents rather
          // than the profile's embedded copy — the profile caps every list
          // it carries at 50 rows, and a client with a longer history needs
          // more than that.
          _InvoicesTab(clientId: _clientId),
          // Same reasoning, same endpoint, `type: 'quotation'` instead.
          _QuotesTab(clientId: _clientId),
          if (_showPayments) _PaymentsTab(clientId: _clientId),
          CrmAsyncView(
            value: profile,
            errorTitle: 'Could not load this client',
            onRetry: () => ref.invalidate(clientProfileProvider(_clientId)),
            builder: (data) => _PeopleTab(profile: data),
          ),
          _ActivityTab(clientId: _clientId),
        ],
      ),
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String verb,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error)
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(verb),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Which of the two clients a merge keeps. Returns `'first'`, `'second'`, or
/// null on Cancel — `first` is always the profile already open, matching
/// what `StaffService.mergeClients`'s `keep` parameter expects.
Future<String?> _chooseMergeSurvivor(
  BuildContext context, {
  required StaffClient first,
  required StaffClient second,
}) {
  var choice = 'first';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Which client survives?'),
        content: RadioGroup<String>(
          groupValue: choice,
          onChanged: (value) => setState(() => choice = value ?? choice),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                value: 'first',
                contentPadding: EdgeInsets.zero,
                title: Text(first.name),
              ),
              RadioListTile<String>(
                value: 'second',
                contentPadding: EdgeInsets.zero,
                title: Text(second.name),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, choice),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

/// The "verify" step of a merge: what actually moved, named per table,
/// rather than trusting the confirmation dialog's prediction silently.
Future<void> _showMergeSummary(
  BuildContext context,
  ClientMergeResult result, {
  required String survivorName,
}) {
  final moved = result.movedCounts.entries.where((e) => e.value > 0).toList();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clients merged'),
      content: Text(
        moved.isEmpty
            ? 'Nothing needed moving into $survivorName.'
            : 'Moved into $survivorName: '
                  '${moved.map((e) => '${e.value} ${e.key.replaceAll('_', ' ')}').join(', ')}.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

/// The client as the subject: what they owe, who they are, what they buy.
class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.profile});

  final ClientProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final client = profile.client;
    final summary = profile.summary;
    final session = ref.watch(sessionControllerProvider).session;
    final canUpdate = session?.can(Permissions.clientsUpdate) ?? false;
    final canSeeInvoiced =
        session?.can(Permissions.clientProfileTotalInvoiced) ?? false;
    final canSeePaid =
        session?.can(Permissions.clientProfileTotalPaid) ?? false;
    final canSeeBalanceDue =
        session?.can(Permissions.clientProfileBalanceDue) ?? false;
    final canSeeActiveSubscriptions =
        session?.can(Permissions.clientProfileActiveSubscriptions) ?? false;
    final canSeeSubscriptionValue =
        session?.can(Permissions.clientProfileSubscriptionValue) ?? false;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(clientProfileProvider(client.id).future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          _BalanceCard(
            profile: profile,
            showBalance: canSeeBalanceDue,
            showInvoiced: canSeeInvoiced,
            showPaid: canSeePaid,
          ),
          const SizedBox(height: Spacing.md),
          StatRail(
            items: [
              if (canSeeActiveSubscriptions)
                StatRailItem(
                  label: 'Services',
                  value: Formatting.integer(summary.activeSubscriptions),
                ),
              if (canSeeSubscriptionValue)
                StatRailItem(
                  label: 'Monthly',
                  value: Formatting.compact(summary.totalSubscriptionValue),
                ),
              StatRailItem(
                label: 'Invoices',
                value: Formatting.integer(profile.invoices.length),
              ),
              StatRailItem(
                label: 'Tickets',
                value: Formatting.integer(profile.tickets.length),
                emphasis: profile.tickets.isEmpty ? null : status.pending,
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),

          // Identity — the reason a field agent opens this screen at all.
          SectionHeader(
            'Contact',
            trailing: canUpdate
                ? TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<StaffClient>(
                        builder: (_) => ClientFormScreen(existing: client),
                      ),
                    ),
                    child: const Text('Edit'),
                  )
                : null,
          ),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (client.phone != null)
                    CrmDetailRow('Phone', client.phone!),
                  if (client.email != null)
                    CrmDetailRow('Email', client.email!),
                  if (client.address != null)
                    CrmDetailRow('Address', client.address!),
                  if (client.taxId != null)
                    CrmDetailRow('Tax ID', client.taxId!),
                  if (_registrant(client) != null)
                    CrmDetailRow('Registrant', _registrant(client)!),
                  CrmDetailRow(
                    'Client since',
                    profile.clientSince == null
                        ? '—'
                        : Formatting.date(profile.clientSince),
                  ),
                  if (client.phone != null || client.email != null) ...[
                    const SizedBox(height: Spacing.md),
                    ContactActions(phone: client.phone, email: client.email),
                  ],
                ],
              ),
            ),
          ),

          if (profile.subscriptions.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Services'),
            const SizedBox(height: Spacing.sm),
            CrmCardList(
              children: [
                for (final sub in profile.subscriptions)
                  ListTile(
                    title: Text(
                      sub.label ?? sub.productServiceName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CrmStatusLine(
                        status: sub.status,
                        meta: [
                          sub.productServiceName,
                          if (sub.billingCycle != null)
                            sub.billingCycle!.replaceAll('_', ' '),
                          if (sub.nextBill != null)
                            'next ${Formatting.date(sub.nextBill)}',
                        ].join(' · '),
                      ),
                    ),
                    trailing: Money(sub.value),
                  ),
              ],
            ),
          ],

          if (profile.addons.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Addons'),
            const SizedBox(height: Spacing.sm),
            CrmCardList(
              children: [
                for (final addon in profile.addons)
                  ListTile(
                    title: Text(addon.name, style: theme.textTheme.titleSmall),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CrmStatusLine(
                        status: addon.status,
                        meta: (addon.billingCycle ?? '').replaceAll('_', ' '),
                      ),
                    ),
                    trailing: Money(addon.price),
                  ),
              ],
            ),
          ],

          if (profile.domains.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Domains'),
            const SizedBox(height: Spacing.sm),
            CrmCardList(
              children: [
                for (final domain in profile.domains)
                  ListTile(
                    title: Text(
                      domain.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CrmStatusLine(
                        status: domain.status,
                        meta: [
                          if (domain.expiresAt != null)
                            'expires ${Formatting.date(domain.expiresAt)}',
                          if (!domain.autoRenew) 'manual renewal',
                        ].join(' · '),
                      ),
                    ),
                  ),
              ],
            ),
          ],

          if (profile.hostingAccounts.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Hosting'),
            const SizedBox(height: Spacing.sm),
            CrmCardList(
              children: [
                for (final account in profile.hostingAccounts)
                  ListTile(
                    title: Text(
                      account.domain ?? '—',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CrmStatusLine(
                        status: account.status,
                        meta: account.cpanelUsername ?? '',
                      ),
                    ),
                  ),
              ],
            ),
          ],

          if (profile.tickets.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Tickets'),
            const SizedBox(height: Spacing.sm),
            CrmCardList(
              children: [
                for (final ticket in profile.tickets)
                  ListTile(
                    onTap: () => context.push('/tickets/${ticket.id}'),
                    title: Text(
                      ticket.subject,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CrmStatusLine(
                        status: ticket.status,
                        meta: [
                          if (ticket.ticketNumber != null) ticket.ticketNumber!,
                          if (ticket.lastReplyAt != null)
                            Formatting.date(ticket.lastReplyAt),
                        ].join(' · '),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
              ],
            ),
          ],

          const SizedBox(height: Spacing.lg),
          SectionHeader(
            'Staff notes',
            trailing: canUpdate
                ? TextButton(
                    onPressed: () => showCrmSheet<void>(
                      context: context,
                      builder: (_) => _NotesSheet(profile: profile),
                    ),
                    child: Text(profile.adminNotes == null ? 'Add' : 'Edit'),
                  )
                : null,
          ),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Text(
                profile.adminNotes ??
                    'Nothing recorded. Never shown to the '
                        'client.',
                style: profile.adminNotes == null
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )
                    : theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The WHMCS-style registrant, collapsed to one line — it only matters as a
  /// whole, and nine separate rows would bury the phone number above it.
  static String? _registrant(StaffClient client) {
    final parts = [
      [
        client.firstName,
        client.lastName,
      ].where((p) => p != null && p.isNotEmpty).join(' '),
      client.companyName ?? '',
      client.address1 ?? '',
      client.address2 ?? '',
      [
        client.city,
        client.state,
        client.postcode,
      ].where((p) => p != null && p.isNotEmpty).join(' '),
      client.country ?? '',
    ].where((p) => p.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// The one figure the screen is about, set as this app sets a figure that
/// matters: display face, on its own, with the two numbers it is the
/// difference of underneath.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.profile,
    this.showBalance = true,
    this.showInvoiced = true,
    this.showPaid = true,
  });

  final ClientProfile profile;

  /// Per-field gates mirroring web's `client_profile.*` permissions — the
  /// backend doesn't withhold this data, so these only match web's own
  /// (cosmetic) display behaviour rather than closing a real leak.
  final bool showBalance;
  final bool showInvoiced;
  final bool showPaid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final summary = profile.summary;
    final owed = summary.balance > 0.005;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    showBalance ? (owed ? 'OUTSTANDING' : 'SETTLED') : 'STATUS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                StatusChip(profile.clientStatus, dense: true),
                if (profile.isReseller) ...[
                  const SizedBox(width: Spacing.sm),
                  StatusChip('reseller', dense: true),
                ],
              ],
            ),
            if (showBalance) ...[
              const SizedBox(height: Spacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Money(
                  summary.balance,
                  scale: MoneyScale.display,
                  display: true,
                  color: owed ? status.overdue : status.settled,
                ),
              ),
            ],
            const SizedBox(height: Spacing.md),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: Spacing.sm),
            if (showInvoiced)
              _Figure(label: 'Invoiced', amount: summary.totalInvoiced),
            if (showPaid) _Figure(label: 'Paid', amount: summary.totalPaid),
            _Figure(
              label: 'Wallet',
              amount: profile.creditBalance,
              emphasis: profile.creditBalance > 0.005 ? status.settled : null,
            ),
            if (profile.isReseller && profile.resellerExpiresAt != null) ...[
              const SizedBox(height: Spacing.xs),
              CrmMetaLine(
                'Reseller until ${Formatting.date(profile.resellerExpiresAt)}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A named amount on the balance card — label left, figure right, so the
/// three of them read as one column of money.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.amount, this.emphasis});

  final String label;
  final Object? amount;
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Money(amount, color: emphasis),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Invoices
// ---------------------------------------------------------------------------

/// This client's invoices, paged — plus the status filter and running
/// totals footer the web profile shows. Filtering re-fetches from page 1
/// (the API filters server-side, same as the tenant-wide documents list);
/// the totals footer accumulates from whatever pages the fetch has actually
/// returned, since [StaffInvoiceRow] carries `total` but not the
/// subtotal/late-fee/paid/balance split the web's full, unpaginated table
/// sums separately — that finer breakdown only exists on the profile's own
/// (50-row-capped) copy, which is exactly what this tab exists to get past.
class _InvoicesTab extends ConsumerStatefulWidget {
  const _InvoicesTab({required this.clientId});

  final String clientId;

  @override
  ConsumerState<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends ConsumerState<_InvoicesTab> {
  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('sent', 'Unpaid'),
    ('paid', 'Paid'),
    ('overdue', 'Overdue'),
    ('cancelled', 'Cancelled'),
  ];

  final _listKey = GlobalKey<PagedListViewState>();
  String? _status;
  double _loadedTotal = 0;
  int _loadedCount = 0;
  int _serverTotal = 0;

  Future<Paginated<StaffInvoiceRow>> _fetch(int page) async {
    final result = await ref
        .read(staffServiceProvider)
        .documents(clientId: widget.clientId, status: _status, page: page);
    if (!mounted) return result;
    setState(() {
      // Page 1 is both the first load and every pull-to-refresh — either
      // way the running total starts over rather than double-counting.
      if (page == 1) {
        _loadedTotal = 0;
        _loadedCount = 0;
      }
      for (final row in result.items) {
        _loadedTotal += row.total;
      }
      _loadedCount += result.items.length;
      _serverTotal = result.total;
    });
    return result;
  }

  void _onFilter(String? status) {
    setState(() {
      _status = status;
      _loadedTotal = 0;
      _loadedCount = 0;
    });
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FilterStrip(options: _filters, selected: _status, onSelect: _onFilter),
      Expanded(
        child: PagedListView<StaffInvoiceRow>(
          key: _listKey,
          fetch: _fetch,
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            0,
            Spacing.md,
            Spacing.xl,
          ),
          itemBuilder: (context, doc) => InkWell(
            borderRadius: Radii.card,
            onTap: () => context.push('/documents/${doc.id}'),
            // The masthead already names the client; repeating it on every
            // row would leave the invoice itself unidentified.
            child: StaffInvoiceCard(document: doc, showClient: false),
          ),
          emptyIcon: Icons.receipt_long_outlined,
          emptyTitle: 'No invoices for this client',
          emptyMessage: 'Invoices raised for them will appear here.',
        ),
      ),
      if (_loadedCount > 0)
        _TotalsFooter(
          count: _loadedCount,
          serverTotal: _serverTotal,
          amount: _loadedTotal,
        ),
    ],
  );
}

/// Sits under a paged list once at least one row has loaded — "so far"
/// rather than "in total" until every page has, since the amount can only
/// be as complete as what has actually been fetched.
class _TotalsFooter extends StatelessWidget {
  const _TotalsFooter({
    required this.count,
    required this.serverTotal,
    required this.amount,
  });

  final int count;
  final int serverTotal;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = count >= serverTotal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              complete
                  ? 'Total · ${Formatting.integer(count)}'
                  : '$count of ${Formatting.integer(serverTotal)} loaded',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Money(amount, scale: MoneyScale.row),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quotes
// ---------------------------------------------------------------------------

/// This client's quotations, paged the same way invoices are — the profile's
/// own `quotations` list is capped at 50, so a busy client needs the real
/// endpoint rather than that shortcut.
class _QuotesTab extends ConsumerWidget {
  const _QuotesTab({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PagedListView(
    fetch: (page) => ref
        .read(staffServiceProvider)
        .documents(type: 'quotation', clientId: clientId, page: page),
    padding: const EdgeInsets.fromLTRB(
      Spacing.md,
      Spacing.md,
      Spacing.md,
      Spacing.xl,
    ),
    itemBuilder: (context, doc) => InkWell(
      borderRadius: Radii.card,
      onTap: () => context.push('/documents/${doc.id}'),
      child: StaffInvoiceCard(document: doc, showClient: false),
    ),
    emptyIcon: Icons.description_outlined,
    emptyTitle: 'No quotes for this client',
    emptyMessage: 'Quotations raised for them will appear here.',
  );
}

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

/// Money received from this client — `payments_in.read`, gated one tab
/// higher up so the whole tab is absent rather than shown empty to a role
/// that cannot see it.
class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PagedListView(
    fetch: (page) => ref
        .read(billingMoneyServiceProvider)
        .paymentsIn(clientId: clientId, page: page),
    padding: const EdgeInsets.fromLTRB(
      Spacing.md,
      Spacing.md,
      Spacing.md,
      Spacing.xl,
    ),
    itemBuilder: (context, payment) => Card(
      child: ListTile(
        title: Text(Formatting.date(payment.paymentDate)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: CrmMetaLine(
            [
              if (payment.paymentMethod != null) payment.paymentMethod!,
              if (payment.reference != null) payment.reference!,
              if (payment.documentNumber != null) payment.documentNumber!,
            ].join(' · '),
          ),
        ),
        trailing: Money(payment.amount),
      ),
    ),
    emptyIcon: Icons.payments_outlined,
    emptyTitle: 'No payments for this client',
    emptyMessage: 'Payments recorded against them will appear here.',
  );
}

// ---------------------------------------------------------------------------
// People
// ---------------------------------------------------------------------------

/// Everyone at the client other than the record itself: the additional
/// contacts, and the portal logins that let them into the client portal.
class _PeopleTab extends ConsumerWidget {
  const _PeopleTab({required this.profile});

  final ClientProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clientId = profile.client.id;
    final session = ref.watch(sessionControllerProvider).session;
    final canUpdate = session?.can(Permissions.clientsUpdate) ?? false;
    // Contacts sit behind clients.update on the API — read included — so a
    // read-only role gets the profile's copy and no editor.
    final contacts = canUpdate
        ? ref.watch(clientContactsProvider(clientId))
        : AsyncValue<List<ClientContact>>.data(profile.contacts);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(clientContactsProvider(clientId));
        ref.invalidate(clientProfileProvider(clientId));
        await ref.read(clientProfileProvider(clientId).future);
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
          SectionHeader(
            'Additional contacts',
            trailing: canUpdate
                ? TextButton(
                    onPressed: () => showCrmSheet<void>(
                      context: context,
                      builder: (_) => _ContactSheet(clientId: clientId),
                    ),
                    child: const Text('Add'),
                  )
                : null,
          ),
          const SizedBox(height: Spacing.sm),
          contacts.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => ErrorBanner(
              message: error is ApiException
                  ? error.message
                  : 'Could not load contacts.',
              onRetry: () => ref.invalidate(clientContactsProvider(clientId)),
            ),
            data: (rows) => rows.isEmpty
                ? Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Text(
                        'Nobody else recorded at this client yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : CrmCardList(
                    children: [
                      for (final contact in rows)
                        ListTile(
                          onTap: !canUpdate
                              ? null
                              : () => showCrmSheet<void>(
                                  context: context,
                                  builder: (_) => _ContactSheet(
                                    clientId: clientId,
                                    existing: contact,
                                  ),
                                ),
                          title: Text(
                            contact.name,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: CrmMetaLine(
                              [
                                if (contact.role != null) contact.role!,
                                if (contact.phone != null) contact.phone!,
                                if (contact.email != null) contact.email!,
                              ].join(' · '),
                            ),
                          ),
                          trailing: contact.phone == null
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.call_outlined),
                                  color: scheme.primary,
                                  tooltip: 'Call ${contact.phone}',
                                  onPressed: () => launchUrl(
                                    Uri(scheme: 'tel', path: contact.phone),
                                  ),
                                ),
                        ),
                    ],
                  ),
          ),

          if (canUpdate) ...[
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Portal access'),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'A portal login lets the client see their own invoices '
                      'and services. Existing logins are managed under Portal '
                      'users.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('Create portal login'),
                      onPressed: () => showCrmSheet<void>(
                        context: context,
                        builder: (_) => _PortalUserSheet(profile: profile),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------

/// This client's follow-up call history — `menu.followups` gates it, same as
/// satisfaction calls sit behind their own menu permission just below.
final AutoDisposeFutureProviderFamily<List<FollowupEntry>, String>
_clientFollowupHistoryProvider = FutureProvider.autoDispose
    .family<List<FollowupEntry>, String>(
      (ref, clientId) =>
          ref.watch(crmServiceProvider).clientFollowupHistory(clientId),
    );

/// What has passed between us and this client: the messages the system sent,
/// the follow-up calls chasing an invoice, and the satisfaction calls staff
/// made.
class _ActivityTab extends ConsumerWidget {
  const _ActivityTab({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final session = ref.watch(sessionControllerProvider).session;
    final canFollowups = session?.can(CrmPermissions.followups) ?? false;
    final canSatisfaction =
        session?.can(CrmPermissions.satisfactionCalls) ?? false;
    final logs = ref.watch(clientCommunicationsProvider(clientId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_clientFollowupHistoryProvider(clientId));
        ref.invalidate(clientSatisfactionProvider(clientId));
        ref.invalidate(clientCommunicationsProvider(clientId));
        await ref.read(clientCommunicationsProvider(clientId).future);
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
          const SectionHeader('Messages sent'),
          const SizedBox(height: Spacing.sm),
          logs.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => ErrorBanner(
              message: error is ApiException
                  ? error.message
                  : 'Could not load the communication log.',
              onRetry: () =>
                  ref.invalidate(clientCommunicationsProvider(clientId)),
            ),
            data: (rows) => rows.isEmpty
                ? Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Text(
                        'Nothing has been sent to this client yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : CrmCardList(
                    children: [
                      for (final log in rows)
                        ListTile(
                          onTap: () => showCrmSheet<void>(
                            context: context,
                            builder: (_) => _MessageSheet(log: log),
                          ),
                          title: Text(
                            log.subject ?? log.type ?? log.channel,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: CrmStatusLine(
                              status: log.status,
                              meta: [
                                log.channel,
                                if (log.recipient != null) log.recipient!,
                                if (log.sentAt != null)
                                  Formatting.date(log.sentAt),
                              ].join(' · '),
                              tone: log.failed ? status.overdue : null,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),

          if (canFollowups) ...[
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Follow-up calls'),
            const SizedBox(height: Spacing.sm),
            ref
                .watch(_clientFollowupHistoryProvider(clientId))
                .when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(Spacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => ErrorBanner(
                    message: error is ApiException
                        ? error.message
                        : 'Could not load the follow-up history.',
                    onRetry: () =>
                        ref.invalidate(_clientFollowupHistoryProvider(clientId)),
                  ),
                  data: (calls) => calls.isEmpty
                      ? Card(
                          child: Padding(
                            padding: const EdgeInsets.all(Spacing.md),
                            child: Text(
                              'No follow-up calls recorded for this client.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : CrmCardList(
                          children: [
                            for (final call in calls)
                              ListTile(
                                title: Text(
                                  call.outcome?.replaceAll('_', ' ') ??
                                      'Follow-up call',
                                  style: theme.textTheme.titleSmall,
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      CrmStatusLine(
                                        status: call.status,
                                        meta: [
                                          if (call.callDate != null)
                                            Formatting.date(call.callDate),
                                          if (call.assignedTo != null)
                                            call.assignedTo!,
                                        ].join(' · '),
                                      ),
                                      if (call.notes != null &&
                                          call.notes!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          call.notes!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                trailing: call.nextFollowup == null
                                    ? null
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'NEXT',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                          ),
                                          Text(
                                            Formatting.date(
                                              call.nextFollowup,
                                            ),
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                              ),
                          ],
                        ),
                ),
          ],

          if (canSatisfaction) ...[
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Satisfaction calls'),
            const SizedBox(height: Spacing.sm),
            ref
                .watch(clientSatisfactionProvider(clientId))
                .when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(Spacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => ErrorBanner(
                    message: error is ApiException
                        ? error.message
                        : 'Could not load the call history.',
                    onRetry: () =>
                        ref.invalidate(clientSatisfactionProvider(clientId)),
                  ),
                  data: (calls) => calls.isEmpty
                      ? Card(
                          child: Padding(
                            padding: const EdgeInsets.all(Spacing.md),
                            child: Text(
                              'No satisfaction call has been scheduled for '
                              'this client.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : CrmCardList(
                          children: [
                            for (final call in calls)
                              ListTile(
                                title: Text(
                                  call.outcome?.replaceAll('_', ' ') ??
                                      'Scheduled call',
                                  style: theme.textTheme.titleSmall,
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: CrmStatusLine(
                                    status: call.status,
                                    meta: [
                                      if (call.scheduledDate != null)
                                        Formatting.date(call.scheduledDate),
                                      if (call.assignedTo != null)
                                        call.assignedTo!,
                                    ].join(' · '),
                                  ),
                                ),
                                trailing: call.rating == null
                                    ? null
                                    : RatingStars(
                                        rating: call.rating,
                                        compact: true,
                                      ),
                              ),
                          ],
                        ),
                ),
          ],
        ],
      ),
    );
  }
}

/// One communication in full — the body is often the only record of what a
/// client was actually told, and a list row can only show its subject.
class _MessageSheet extends StatelessWidget {
  const _MessageSheet({required this.log});

  final ClientCommunication log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CrmSheet(
      eyebrow: log.channel,
      title: log.subject ?? log.type ?? 'Message',
      children: [
        CrmDetailRow('Status', log.status ?? '—'),
        if (log.recipient != null) CrmDetailRow('To', log.recipient!),
        if (log.sentAt != null)
          CrmDetailRow('Sent', Formatting.dateTime(log.sentAt)),
        if (log.error != null) CrmDetailRow('Error', log.error!),
        if (log.message != null) ...[
          const SizedBox(height: Spacing.md),
          // Email bodies are stored as HTML; the tags are noise on a phone
          // and the words are the record.
          Text(
            htmlToPlainText(log.message!),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// Everything that writes to this client, gathered behind the masthead's
/// action button. Each entry is gated on exactly the permission its route
/// enforces, so an action that would only 403 is never offered.
class _ActionsSheet extends ConsumerWidget {
  const _ActionsSheet({required this.profile});

  final ClientProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).session;
    bool can(String permission) => session?.can(permission) ?? false;
    final scheme = Theme.of(context).colorScheme;
    final status = context.statusColors;

    final canUpdate = can(Permissions.clientsUpdate);
    final canCredit = can(Permissions.creditManage);
    final canPortalLogin = can(Permissions.clientsPortalLogin);
    // Delete and merge share this permission on the server — both move or
    // destroy another record's history, so both sit behind the same gate.
    final canDelete = can(Permissions.clientsDelete);
    final hasCredit = profile.creditBalance > 0.005;
    final hasUnpaid = profile.unpaidInvoices.isNotEmpty;

    return CrmSheet(
      eyebrow: 'Client',
      title: profile.client.name,
      children: [
        if (canPortalLogin)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.login),
            title: const Text('Login as this client'),
            subtitle: const Text("Opens their portal, in this client's shoes"),
            onTap: () => Navigator.of(context).pop('portal-login'),
          ),
        if (canUpdate)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit client'),
            subtitle: const Text('Name, contact and registrant details'),
            onTap: () => Navigator.of(context).pop('edit'),
          ),
        if (canUpdate)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: const Text('Staff notes'),
            subtitle: const Text('Never shown to the client'),
            onTap: () => Navigator.of(context).pop('notes'),
          ),
        if (canCredit)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Adjust credit'),
            subtitle: Text(
              'Wallet holds ${Formatting.currency(profile.creditBalance)}',
            ),
            onTap: () => Navigator.of(context).pop('credit'),
          ),
        if (canCredit && hasCredit && hasUnpaid)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.playlist_add_check),
            title: const Text('Apply credit to an invoice'),
            subtitle: const Text('Spends the wallet against what is owed'),
            onTap: () => Navigator.of(context).pop('apply-credit'),
          ),
        if (canUpdate && !profile.isReseller)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Make reseller'),
            subtitle: const Text('Raises the annual membership invoice'),
            onTap: () => Navigator.of(context).pop('reseller'),
          ),
        if (canDelete) ...[
          const Divider(height: Spacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.call_merge, color: status.pending),
            title: const Text('Merge with another client'),
            subtitle: const Text('Moves everything into whichever survives'),
            onTap: () => Navigator.of(context).pop('merge'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: scheme.error),
            title: Text('Delete client', style: TextStyle(color: scheme.error)),
            subtitle: const Text('Removes the client record — irreversible'),
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ],
    );
  }
}

/// Staff-only notes. One field, because that is exactly what the route takes.
class _NotesSheet extends ConsumerStatefulWidget {
  const _NotesSheet({required this.profile});

  final ClientProfile profile;

  @override
  ConsumerState<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends ConsumerState<_NotesSheet> {
  late final TextEditingController _notes = TextEditingController(
    text: widget.profile.adminNotes ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final clientId = widget.profile.client.id;
    final text = _notes.text.trim();
    try {
      final message = await ref
          .read(staffServiceProvider)
          .updateClientNotes(clientId, text.isEmpty ? null : text);
      ref.invalidate(clientProfileProvider(clientId));
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Notes saved.')),
      );
      if (navigator.canPop()) navigator.pop();
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
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: widget.profile.client.name,
    title: 'Staff notes',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmField(
        label: 'Notes',
        child: TextField(
          controller: _notes,
          enabled: !_saving,
          autofocus: true,
          minLines: 5,
          maxLines: 12,
          maxLength: 10000,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: 'What the next person needs to know',
          ),
        ),
      ),
      const SizedBox(height: Spacing.sm),
      PrimaryButton(
        label: _saving ? 'Saving…' : 'Save notes',
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
    ],
  );
}

/// Add or remove wallet credit. The API demands a reason, because the ledger
/// entry is the only audit trail this movement leaves.
class _AdjustCreditSheet extends ConsumerStatefulWidget {
  const _AdjustCreditSheet({required this.profile});

  final ClientProfile profile;

  @override
  ConsumerState<_AdjustCreditSheet> createState() => _AdjustCreditSheetState();
}

class _AdjustCreditSheetState extends ConsumerState<_AdjustCreditSheet> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  bool _adding = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final magnitude = double.tryParse(
      _amount.text.replaceAll(RegExp(r'[^0-9.]'), '').trim(),
    );
    if (magnitude == null || magnitude <= 0) {
      setState(() => _error = 'Enter how much to move.');
      return;
    }
    final reason = _notes.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Say why — the ledger keeps this.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final clientId = widget.profile.client.id;
    try {
      final message = await ref
          .read(staffServiceProvider)
          .adjustClientCredit(
            clientId,
            amount: _adding ? magnitude : -magnitude,
            notes: reason,
          );
      ref.invalidate(clientProfileProvider(clientId));
      ref.invalidate(clientCreditProvider(clientId));
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Wallet updated.')),
      );
      if (navigator.canPop()) navigator.pop();
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
    return CrmSheet(
      eyebrow: widget.profile.client.name,
      title: 'Adjust credit',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Wallet balance', style: theme.textTheme.titleSmall),
            Money(widget.profile.creditBalance),
          ],
        ),
        const SizedBox(height: Spacing.md),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Add')),
            ButtonSegment(value: false, label: Text('Remove')),
          ],
          selected: {_adding},
          onSelectionChanged: _saving
              ? null
              : (values) => setState(() => _adding = values.first),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Amount',
          child: TextField(
            controller: _amount,
            enabled: !_saving,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '0.00'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Reason',
          child: TextField(
            controller: _notes,
            enabled: !_saving,
            maxLength: 255,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Why the wallet is moving',
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        PrimaryButton(
          label: _saving
              ? 'Saving…'
              : (_adding ? 'Add credit' : 'Remove credit'),
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

/// Spend the wallet against one of the client's unpaid invoices. The API
/// decides how much moves — as much as the balance takes — so this only has
/// to name the invoice.
class _ApplyCreditSheet extends ConsumerStatefulWidget {
  const _ApplyCreditSheet({required this.profile});

  final ClientProfile profile;

  @override
  ConsumerState<_ApplyCreditSheet> createState() => _ApplyCreditSheetState();
}

class _ApplyCreditSheetState extends ConsumerState<_ApplyCreditSheet> {
  String? _busyId;
  String? _error;

  Future<void> _apply(ClientInvoiceRow invoice) async {
    setState(() {
      _busyId = invoice.id;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final clientId = widget.profile.client.id;
    try {
      final message = await ref
          .read(staffServiceProvider)
          .applyCreditToInvoice(invoice.id);
      ref.invalidate(clientProfileProvider(clientId));
      ref.invalidate(clientCreditProvider(clientId));
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Credit applied.')),
      );
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busyId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invoices = widget.profile.unpaidInvoices;

    return CrmSheet(
      eyebrow: widget.profile.client.name,
      title: 'Apply credit',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Wallet balance', style: theme.textTheme.titleSmall),
            Money(widget.profile.creditBalance),
          ],
        ),
        const SizedBox(height: Spacing.md),
        CrmCardList(
          children: [
            for (final invoice in invoices)
              ListTile(
                enabled: _busyId == null,
                onTap: () => _apply(invoice),
                title: Text(
                  invoice.documentNumber,
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: CrmStatusLine(
                    status: invoice.status,
                    meta: invoice.dueDate == null
                        ? ''
                        : 'due ${Formatting.date(invoice.dueDate)}',
                  ),
                ),
                trailing: _busyId == invoice.id
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Money(invoice.balanceDue),
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        Text(
          'As much of the wallet as the invoice needs is recorded against it '
          'as a payment.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Add, edit or remove one additional contact.
class _ContactSheet extends ConsumerStatefulWidget {
  const _ContactSheet({required this.clientId, this.existing});

  final String clientId;
  final ClientContact? existing;

  @override
  ConsumerState<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<_ContactSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _role = TextEditingController(
    text: widget.existing?.role ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.existing?.phone ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.existing?.email ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.existing?.notes ?? '',
  );

  bool _saving = false;
  String? _error;

  ClientContact? get _existing => widget.existing;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _value(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  void _refresh() {
    ref.invalidate(clientContactsProvider(widget.clientId));
    ref.invalidate(clientProfileProvider(widget.clientId));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'A name is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final service = ref.read(staffServiceProvider);
    final existing = _existing;
    try {
      final message = existing == null
          ? await service.createClientContact(
              widget.clientId,
              name: name,
              email: _value(_email),
              phone: _value(_phone),
              role: _value(_role),
              notes: _value(_notes),
            )
          : await service.updateClientContact(
              widget.clientId,
              existing.id,
              name: name,
              email: _value(_email),
              phone: _value(_phone),
              role: _value(_role),
              notes: _value(_notes),
            );
      _refresh();
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Contact saved.')),
      );
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }

  Future<void> _remove() async {
    final existing = _existing;
    if (existing == null) return;
    final confirmed = await _confirm(
      context,
      title: 'Remove ${existing.name}?',
      body: 'They stop appearing as a contact for this client.',
      verb: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final message = await ref
          .read(staffServiceProvider)
          .deleteClientContact(widget.clientId, existing.id);
      _refresh();
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Contact removed.')),
      );
      if (navigator.canPop()) navigator.pop();
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
    final scheme = Theme.of(context).colorScheme;
    return CrmSheet(
      eyebrow: 'Additional contact',
      title: _existing == null ? 'Add contact' : _existing!.name,
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_saving,
            autofocus: _existing == null,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Who they are'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Role',
          child: TextField(
            controller: _role,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Accountant'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Phone',
          child: TextField(
            controller: _phone,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '+255 7xx xxx xxx'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Email',
          child: TextField(
            controller: _email,
            enabled: !_saving,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'name@example.co.tz'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes',
          child: TextField(
            controller: _notes,
            enabled: !_saving,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(hintText: 'Anything useful'),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        PrimaryButton(
          label: _saving ? 'Saving…' : 'Save contact',
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
        if (_existing != null)
          TextButton(
            onPressed: _saving ? null : _remove,
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Remove contact'),
          ),
      ],
    );
  }
}

/// Create a portal login for the client — the one portal-user verb the app
/// could not do. Editing and removing an existing login live under Portal
/// users, which is where they already were.
class _PortalUserSheet extends ConsumerStatefulWidget {
  const _PortalUserSheet({required this.profile});

  final ClientProfile profile;

  @override
  ConsumerState<_PortalUserSheet> createState() => _PortalUserSheetState();
}

class _PortalUserSheetState extends ConsumerState<_PortalUserSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.client.name,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.profile.client.email ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.profile.client.phone ?? '',
  );
  final _password = TextEditingController();

  String _role = 'admin';
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'A name and an email address are both required.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'The password must be at least 8 characters.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final phone = _phone.text.trim();
    try {
      final message = await ref
          .read(staffServiceProvider)
          .createClientPortalUser(
            widget.profile.client.id,
            name: name,
            email: email,
            password: password,
            role: _role,
            phone: phone.isEmpty ? null : phone,
          );
      ref.invalidate(clientProfileProvider(widget.profile.client.id));
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Portal user created.')),
      );
      if (navigator.canPop()) navigator.pop();
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
    return CrmSheet(
      eyebrow: widget.profile.client.name,
      title: 'Create portal login',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Who signs in'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Email',
          child: TextField(
            controller: _email,
            enabled: !_saving,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'name@example.co.tz'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Phone',
          child: TextField(
            controller: _phone,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Password',
          child: TextField(
            controller: _password,
            enabled: !_saving,
            obscureText: _obscure,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'At least 8 characters',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Role',
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'admin', label: Text('Admin')),
              ButtonSegment(value: 'viewer', label: Text('Viewer')),
            ],
            selected: {_role},
            onSelectionChanged: _saving
                ? null
                : (values) => setState(() => _role = values.first),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          'An admin can order and pay; a viewer can only look. Tell the client '
          'their password yourself — it is not emailed.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        PrimaryButton(
          label: _saving ? 'Creating…' : 'Create login',
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

/// Call / email action row used where a client's contacts are shown.
///
/// Secondary actions in the theme's outlined button, the icon quiet — the
/// word is the action; the icon only disambiguates the two.
class ContactActions extends StatelessWidget {
  const ContactActions({super.key, this.phone, this.email});

  final String? phone;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (phone != null)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.call_outlined, size: 18),
              label: const Text('Call'),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            ),
          ),
        if (phone != null && email != null) const SizedBox(width: Spacing.sm),
        if (email != null)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text('Email'),
              onPressed: () => launchUrl(Uri(scheme: 'mailto', path: email)),
            ),
          ),
      ],
    );
  }
}

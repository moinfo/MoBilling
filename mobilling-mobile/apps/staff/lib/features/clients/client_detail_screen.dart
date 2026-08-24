import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

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
        RatingStars,
        showCrmSheet;
import '../documents/documents_tab.dart' show StaffInvoiceCard;
import 'client_form_screen.dart';
import 'client_providers.dart';

/// One client, as a profile rather than as a list of their invoices.
///
/// The subject of the screen is the person or company; the figure it is about
/// is what they owe. Everything else is a section under that — what they buy,
/// who else works there, what we have sent them — with the invoice list kept
/// intact on its own tab, paged exactly as it was.
///
/// Editing lives here now: the record, the staff notes, the wallet, the
/// additional contacts and portal access are all reachable without a browser.
/// Merging two clients and deleting one deliberately are not — both are
/// reconciliation work with a blast radius no phone screen should carry.
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
  late final TabController _tabs = TabController(length: 4, vsync: this);

  String get _clientId => widget.clientId;

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
          tabs: const ['Overview', 'Invoices', 'People', 'Activity'],
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
          // The invoice list is unchanged: its own paging, its own empty
          // state, and still without the client's name on every row — the
          // masthead already says whose these are.
          _InvoicesTab(clientId: _clientId),
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
          _BalanceCard(profile: profile),
          const SizedBox(height: Spacing.md),
          StatRail(
            items: [
              StatRailItem(
                label: 'Services',
                value: Formatting.integer(summary.activeSubscriptions),
              ),
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
  const _BalanceCard({required this.profile});

  final ClientProfile profile;

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
                    owed ? 'OUTSTANDING' : 'SETTLED',
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
            const SizedBox(height: Spacing.md),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: Spacing.sm),
            _Figure(label: 'Invoiced', amount: summary.totalInvoiced),
            _Figure(label: 'Paid', amount: summary.totalPaid),
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

/// The screen's original body, unchanged: this client's invoices, paged.
class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PagedListView(
    fetch: (page) => ref
        .read(staffServiceProvider)
        .documents(clientId: clientId, page: page),
    padding: const EdgeInsets.fromLTRB(
      Spacing.md,
      Spacing.md,
      Spacing.md,
      Spacing.xl,
    ),
    itemBuilder: (context, doc) => InkWell(
      borderRadius: Radii.card,
      onTap: () => context.push('/documents/${doc.id}'),
      // The masthead already names the client; repeating it on every row
      // would leave the invoice itself unidentified.
      child: StaffInvoiceCard(document: doc, showClient: false),
    ),
    emptyIcon: Icons.receipt_long_outlined,
    emptyTitle: 'No invoices for this client',
    emptyMessage: 'Invoices raised for them will appear here.',
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

/// What has passed between us and this client: the messages the system sent,
/// and the satisfaction calls staff made.
class _ActivityTab extends ConsumerWidget {
  const _ActivityTab({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final session = ref.watch(sessionControllerProvider).session;
    final canSatisfaction =
        session?.can(CrmPermissions.satisfactionCalls) ?? false;
    final logs = ref.watch(clientCommunicationsProvider(clientId));

    return RefreshIndicator(
      onRefresh: () async {
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

    final canUpdate = can(Permissions.clientsUpdate);
    final canCredit = can(Permissions.creditManage);
    final hasCredit = profile.creditBalance > 0.005;
    final hasUnpaid = profile.unpaidInvoices.isNotEmpty;

    return CrmSheet(
      eyebrow: 'Client',
      title: profile.client.name,
      children: [
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
        const Divider(height: Spacing.lg),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: const Text('Merging and deleting stay on the web'),
          subtitle: const Text(
            'Both move or destroy history across the whole account.',
          ),
          enabled: false,
        ),
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

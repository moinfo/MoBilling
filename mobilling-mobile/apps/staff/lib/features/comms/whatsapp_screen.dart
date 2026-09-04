import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../common/pickers.dart';
import '../crm/crm_providers.dart';
import '../crm/crm_ui.dart';
import '../crm/marketing_services_screen.dart';
import 'comms_providers.dart';
import 'comms_ui.dart';

final AutoDisposeFutureProvider<List<WhatsappContact>>
whatsappContactsProvider = FutureProvider.autoDispose<List<WhatsappContact>>(
  (ref) => ref.watch(commsServiceProvider).whatsappContacts(),
);

final AutoDisposeFutureProvider<WhatsappContactStats> whatsappStatsProvider =
    FutureProvider.autoDispose<WhatsappContactStats>(
      (ref) => ref.watch(commsServiceProvider).whatsappContactStats(),
    );

final AutoDisposeFutureProvider<List<WhatsappCampaign>>
whatsappCampaignsProvider = FutureProvider.autoDispose<List<WhatsappCampaign>>(
  (ref) => ref.watch(commsServiceProvider).whatsappCampaigns(),
);

final AutoDisposeFutureProviderFamily<List<WhatsappFollowup>, String>
whatsappFollowupsProvider = FutureProvider.autoDispose
    .family<List<WhatsappFollowup>, String>(
      (ref, contactId) =>
          ref.watch(commsServiceProvider).whatsappFollowups(contactId),
    );

enum _WaSection { contacts, due, campaigns }

/// The WhatsApp marketing pipeline: leads, the calls due on them, and the paid
/// campaigns they came from.
///
/// One screen with three sections rather than three routes, because the whole
/// point of the pipeline is moving between them.
class WhatsappScreen extends ConsumerStatefulWidget {
  const WhatsappScreen({super.key});

  @override
  ConsumerState<WhatsappScreen> createState() => _WhatsappScreenState();
}

class _WhatsappScreenState extends ConsumerState<WhatsappScreen> {
  _WaSection _section = _WaSection.contacts;

  @override
  Widget build(BuildContext context) {
    final onCampaigns = _section == _WaSection.campaigns;
    final canAddContact = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappContactsCreate),
    );
    final canAddCampaign = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappCampaignsCreate),
    );
    final canViewAll = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappContactsViewAll),
    );
    // Bulk claim only means something while there is something unowned to
    // claim, and the contacts list is already in memory.
    final unowned =
        ref
            .watch(whatsappContactsProvider)
            .valueOrNull
            ?.where((c) => c.createdBy == null)
            .length ??
        0;
    final canBulkClaim = canViewAll && !onCampaigns && unowned > 0;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Engagement',
        title: 'WhatsApp',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canBulkClaim)
              InkActionButton(
                icon: Icons.group_add_outlined,
                tooltip: 'Claim $unowned unowned contacts',
                onPressed: _claimAll,
              ),
            if (onCampaigns && canAddCampaign)
              Padding(
                padding: EdgeInsets.only(left: canBulkClaim ? Spacing.sm : 0),
                child: InkActionButton(
                  icon: Icons.campaign_outlined,
                  tooltip: 'New campaign',
                  onPressed: () => _editCampaign(null),
                ),
              ),
            if (!onCampaigns && canAddContact)
              Padding(
                padding: EdgeInsets.only(left: canBulkClaim ? Spacing.sm : 0),
                child: InkActionButton(
                  icon: Icons.person_add_alt_1_outlined,
                  tooltip: 'Add a contact',
                  onPressed: _addContact,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          SectionSelector<_WaSection>(
            sections: const [
              (_WaSection.contacts, 'Contacts'),
              (_WaSection.due, 'Due'),
              (_WaSection.campaigns, 'Campaigns'),
            ],
            selected: _section,
            onSelected: (value) => setState(() => _section = value),
          ),
          Expanded(
            child: switch (_section) {
              _WaSection.contacts => const _ContactsView(dueOnly: false),
              _WaSection.due => const _ContactsView(dueOnly: true),
              _WaSection.campaigns => const _CampaignsView(),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addContact() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: commsSheetShape,
      builder: (_) => const _ContactFormSheet(),
    );
    if (saved == true) {
      ref.invalidate(whatsappContactsProvider);
      ref.invalidate(whatsappStatsProvider);
    }
  }

  Future<void> _editCampaign(WhatsappCampaign? campaign) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: commsSheetShape,
      builder: (_) => _CampaignFormSheet(campaign: campaign),
    );
    if (saved == true) ref.invalidate(whatsappCampaignsProvider);
  }

  /// `POST /whatsapp-contacts/claim-bulk` scoped to the contacts on screen —
  /// the server's `whereNull` guard means it can never take someone else's.
  Future<void> _claimAll() async {
    final rows = ref.read(whatsappContactsProvider).valueOrNull ?? const [];
    final ids = [
      for (final contact in rows)
        if (contact.createdBy == null) contact.id,
    ];
    if (ids.isEmpty) return;

    final sure = await _confirmWhatsapp(
      context,
      title:
          'Claim ${ids.length} unowned '
          '${ids.length == 1 ? 'contact' : 'contacts'}?',
      message:
          'They become yours to follow up. Contacts someone else already owns '
          'are left alone.',
      verb: 'Claim',
      destructive: false,
    );
    if (!sure || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final claimed = await ref
          .read(commsServiceProvider)
          .claimWhatsappContactsBulk(ids: ids);
      ref.invalidate(whatsappContactsProvider);
      ref.invalidate(whatsappStatsProvider);
      showCommsMessage(
        messenger,
        '${Formatting.integer(claimed)} '
        '${claimed == 1 ? 'contact' : 'contacts'} claimed.',
      );
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }
}

class _ContactsView extends ConsumerStatefulWidget {
  const _ContactsView({required this.dueOnly});

  /// The due list is derived here rather than server-side: the contacts
  /// endpoint is unpaginated and has no date filter, so the app already holds
  /// every row it needs.
  final bool dueOnly;

  @override
  ConsumerState<_ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends ConsumerState<_ContactsView> {
  final _search = TextEditingController();

  /// Raw `label`/`source` enum values (not the typed enums) — [FilterStrip]
  /// works in strings, and that is what [WhatsappContact] stores them as too.
  String? _label;
  String? _source;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<WhatsappContact> _visible(List<WhatsappContact> all) {
    final query = _search.text.trim().toLowerCase();
    var rows = widget.dueOnly ? all.where((c) => c.isFollowupDue) : all;

    if (_label != null) rows = rows.where((c) => c.label == _label);
    if (_source != null) rows = rows.where((c) => c.source == _source);

    if (query.isNotEmpty) {
      rows = rows.where(
        (c) => c.name.toLowerCase().contains(query) || c.phone.contains(query),
      );
    }

    final list = rows.toList();
    if (widget.dueOnly) {
      // Oldest overdue first — that is the order the calls should be made in.
      list.sort(
        (a, b) => (a.nextFollowupDate ?? DateTime(2100)).compareTo(
          b.nextFollowupDate ?? DateTime(2100),
        ),
      );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(whatsappContactsProvider);
    final stats = ref.watch(whatsappStatsProvider).valueOrNull;

    return Column(
      children: [
        if (!widget.dueOnly) ...[
          const _StatsStrip(),
          FilterStrip(
            options: [
              (null, 'All stages'),
              for (final label in WhatsappLabel.values)
                (
                  label.value,
                  '${label.label} (${stats?.byLabel[label.value] ?? 0})',
                ),
            ],
            selected: _label,
            onSelect: (value) => setState(() => _label = value),
          ),
          FilterStrip(
            options: [
              (null, 'All sources'),
              for (final source in WhatsappSource.values)
                (
                  source.value,
                  '${source.label} (${stats?.bySource[source.value] ?? 0})',
                ),
            ],
            selected: _source,
            onSelect: (value) => setState(() => _source = value),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.sm,
            ),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name or phone',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: 'Clear search',
                        onPressed: () => setState(() => _search.clear()),
                      ),
              ),
            ),
          ),
        ],
        Expanded(
          child: CommsAsyncView<List<WhatsappContact>>(
            value: contacts,
            errorTitle: 'Could not load contacts',
            onRetry: () => ref.invalidate(whatsappContactsProvider),
            builder: (context, all) {
              final rows = _visible(all);
              if (rows.isEmpty) {
                return StateMessage(
                  icon: widget.dueOnly
                      ? Icons.event_available_outlined
                      : Icons.contacts_outlined,
                  title: widget.dueOnly
                      ? 'No follow-ups due'
                      : 'No contacts found',
                  message: widget.dueOnly
                      ? 'Calls booked for today or earlier appear here.'
                      : null,
                );
              }

              return RefreshIndicator(
                onRefresh: () => ref.refresh(whatsappContactsProvider.future),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) =>
                      _ContactCard(contact: rows[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Pipeline counts as one rail. Converted is the only figure that is itself
/// the news, so it is the only one coloured.
class _StatsStrip extends ConsumerWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(whatsappStatsProvider).valueOrNull;
    if (stats == null) return const SizedBox.shrink();

    final status = context.statusColors;
    final leads = stats.byLabel['lead'] ?? 0;
    final conversionRate = stats.total == 0
        ? 0
        : (stats.converted / stats.total * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.sm,
        Spacing.md,
        Spacing.md,
      ),
      child: Reveal(
        child: StatRail(
          items: [
            StatRailItem(
              label: 'Contacts',
              value: Formatting.integer(stats.total),
            ),
            StatRailItem(label: 'Open leads', value: Formatting.integer(leads)),
            StatRailItem(
              label: 'Converted',
              value: Formatting.integer(stats.converted),
              emphasis: stats.converted > 0 ? status.settled : null,
            ),
            StatRailItem(label: 'Conversion', value: '$conversionRate%'),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact});

  final WhatsappContact contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    final Widget? marker = contact.isConverted
        ? Icon(Icons.verified_outlined, size: 18, color: status.settled)
        : contact.isFollowupDue
        ? Icon(
            Icons.notifications_active_outlined,
            size: 18,
            color: status.attention,
          )
        : null;

    return Card(
      child: ListTile(
        onTap: () => _showContactSheet(context, contact),
        title: Row(
          children: [
            Flexible(
              child: Text(
                contact.name,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (contact.isImportant) ...[
              const SizedBox(width: Spacing.xs),
              Icon(Icons.star_rounded, size: 16, color: status.attention),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Row(
            children: [
              CommsChip(
                label: WhatsappLabel.labelFor(contact.label),
                color: _labelColor(context, contact.label),
              ),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: CommsMeta(
                  [
                    contact.phone,
                    WhatsappSource.labelFor(contact.source),
                    if (contact.nextFollowupDate != null)
                      'follow up ${Formatting.date(contact.nextFollowupDate)}',
                  ].join(' · '),
                ),
              ),
            ],
          ),
        ),
        trailing: marker,
      ),
    );
  }
}

/// Colour for a pipeline stage: money still owed reads as needing attention,
/// a finished order as settled, an untouched lead as neutral.
Color _labelColor(BuildContext context, String label) {
  final colors = context.statusColors;
  return switch (label) {
    'paid' || 'order_complete' => colors.settled,
    'pending_payment' || 'follow_up' => colors.attention,
    'new_customer' || 'new_order' => colors.pending,
    _ => colors.inactive,
  };
}

void _showContactSheet(BuildContext context, WhatsappContact contact) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: commsSheetShape,
    builder: (context) => _ContactSheet(contact: contact),
  );
}

class _ContactSheet extends ConsumerStatefulWidget {
  const _ContactSheet({required this.contact});

  final WhatsappContact contact;

  @override
  ConsumerState<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<_ContactSheet> {
  bool _logging = false;

  /// The contact as the API last returned it, so a convert or a claim shows
  /// in this sheet without waiting for the list behind it.
  WhatsappContact? _updated;

  WhatsappContact get _contact => _updated ?? widget.contact;

  void _refreshLists() {
    ref.invalidate(whatsappContactsProvider);
    ref.invalidate(whatsappStatsProvider);
  }

  Future<void> _claim() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final contact = await ref
          .read(commsServiceProvider)
          .claimWhatsappContact(_contact.id);
      _refreshLists();
      if (mounted) setState(() => _updated = contact);
      showCommsMessage(messenger, 'Contact claimed.');
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }

  /// Release the contact back to the shared pool — the undo for a claim made
  /// by mistake.
  Future<void> _unclaim() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final contact = await ref
          .read(commsServiceProvider)
          .unclaimWhatsappContact(_contact.id);
      _refreshLists();
      if (mounted) setState(() => _updated = contact);
      showCommsMessage(messenger, 'Contact released to the shared pool.');
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }

  Future<void> _assign() async {
    final user = await StaffUserPickerSheet.show(context);
    if (user == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final contact = await ref
          .read(commsServiceProvider)
          .assignWhatsappContact(_contact.id, userId: user.id);
      _refreshLists();
      if (mounted) setState(() => _updated = contact);
      showCommsMessage(messenger, 'Contact assigned to ${user.name}.');
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }

  /// The payoff: a lead that answered becomes a billing client without anyone
  /// going back to a desk.
  Future<void> _convert() async {
    final converted = await showModalBottomSheet<WhatsappContact>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: commsSheetShape,
      builder: (_) => _ConvertContactSheet(contact: _contact),
    );
    if (converted == null || !mounted) return;
    _refreshLists();
    setState(() => _updated = converted);
    showCommsMessage(
      ScaffoldMessenger.of(context),
      converted.clientName == null
          ? '${converted.name} is now a client.'
          : '${converted.name} is now a client — ${converted.clientName}.',
    );
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: commsSheetShape,
      builder: (_) => _ContactFormSheet(contact: _contact),
    );
    if (saved != true || !mounted) return;
    _refreshLists();
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final sure = await _confirmWhatsapp(
      context,
      title: 'Delete ${_contact.name}?',
      message:
          'The contact and every call logged against it are removed for good.',
      verb: 'Delete',
    );
    if (!sure || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(commsServiceProvider).deleteWhatsappContact(_contact.id);
      _refreshLists();
      showCommsMessage(messenger, 'Contact deleted.');
      navigator.pop();
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }

  Future<void> _deleteFollowup(WhatsappFollowup followup) async {
    final sure = await _confirmWhatsapp(
      context,
      title: 'Delete this logged call?',
      message: 'The call comes off ${_contact.name}’s history.',
      verb: 'Delete',
    );
    if (!sure || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(commsServiceProvider)
          .deleteWhatsappFollowup(_contact.id, followup.id);
      ref.invalidate(whatsappFollowupsProvider(_contact.id));
      showCommsMessage(messenger, 'Call removed.');
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }

  Future<void> _openWhatsapp() async {
    // wa.me wants digits only; stored numbers carry spaces, plus signs and
    // dashes depending on who typed them in.
    final digits = _contact.phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    await launchUrl(
      Uri.parse('https://wa.me/$digits'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final contact = _contact;
    final theme = Theme.of(context);
    final status = context.statusColors;
    final followups = ref.watch(whatsappFollowupsProvider(contact.id));
    final canLog = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappContactsLog),
    );
    final canClaim = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappContactsUpdate),
    );
    final canConvert = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappContactsConvert),
    );
    final canDelete = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappContactsDelete),
    );
    final canViewAll = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappContactsViewAll),
    );
    // Reassigning means listing `/users`, gated separately from the route.
    final canAssign =
        canViewAll &&
        ref.watch(commsPermissionProvider(CommsPermissions.settingsUsers));
    final myId = ref.watch(currentUserProvider)?.id;
    // The server lets an owner release their own contact, and view_all
    // holders release anyone's.
    final canUnclaim =
        canClaim &&
        contact.createdBy != null &&
        (contact.createdBy == myId || canViewAll);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.lg + sheetBottomInset(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommsSheetHeader(
              eyebrow: 'WhatsApp contact',
              title: contact.name,
              trailing: CommsChip(
                label: WhatsappLabel.labelFor(contact.label),
                color: _labelColor(context, contact.label),
                dense: false,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('WhatsApp'),
                    onPressed: _openWhatsapp,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Call'),
                    onPressed: () =>
                        launchUrl(Uri(scheme: 'tel', path: contact.phone)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            // Convert leads everything else: a lead that is not yet a client
            // is one tap from becoming one.
            if (contact.isConverted)
              _ConvertedBanner(clientName: contact.clientName)
            else if (canConvert) ...[
              PrimaryButton(
                label: 'Convert to client',
                icon: Icons.how_to_reg_outlined,
                onPressed: _convert,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Creates the client and moves this contact to the new-customer '
                'stage.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            const SectionHeading('Details'),
            DetailRow(label: 'Phone', value: contact.phone),
            DetailRow(
              label: 'Stage',
              value: WhatsappLabel.labelFor(contact.label),
            ),
            DetailRow(
              label: 'Source',
              value: WhatsappSource.labelFor(contact.source),
            ),
            if (contact.services.isNotEmpty)
              DetailRow(label: 'Services', value: contact.services.join(', ')),
            if (contact.campaignName != null)
              DetailRow(label: 'Campaign', value: contact.campaignName!),
            if (contact.clientName != null)
              DetailRow(label: 'Client', value: contact.clientName!),
            if (contact.assignedUserName != null)
              DetailRow(label: 'Assigned', value: contact.assignedUserName!),
            DetailRow(
              label: 'Owner',
              value: contact.creatorName ?? 'Unassigned (shared)',
            ),
            if (contact.nextFollowupDate != null)
              DetailRow(
                label: 'Next call',
                value: Formatting.date(contact.nextFollowupDate),
              ),
            if (contact.notes != null)
              DetailRow(label: 'Notes', value: contact.notes!),
            if (contact.createdBy == null && canClaim) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton.icon(
                icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                label: const Text('Claim this contact'),
                onPressed: _claim,
              ),
            ],
            if (canUnclaim || canAssign) ...[
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  if (canUnclaim)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.person_off_outlined, size: 18),
                        label: Text(
                          contact.createdBy == myId ? 'Release' : 'Unassign',
                        ),
                        onPressed: _unclaim,
                      ),
                    ),
                  if (canUnclaim && canAssign)
                    const SizedBox(width: Spacing.sm),
                  if (canAssign)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.manage_accounts_outlined,
                          size: 18,
                        ),
                        label: const Text('Reassign'),
                        onPressed: _assign,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.lg),
            SectionHeading(
              'Follow-ups',
              trailing: canLog
                  ? TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Log call'),
                      onPressed: _logging
                          ? null
                          : () => setState(() => _logging = true),
                    )
                  : null,
            ),
            if (_logging) ...[
              _LogFollowupForm(
                contactId: contact.id,
                onDone: () {
                  if (mounted) setState(() => _logging = false);
                },
              ),
              const SizedBox(height: Spacing.sm),
            ],
            CommsAsyncView<List<WhatsappFollowup>>(
              value: followups,
              errorTitle: 'Could not load follow-ups',
              onRetry: () =>
                  ref.invalidate(whatsappFollowupsProvider(contact.id)),
              builder: (context, rows) => rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                      child: Text(
                        'No calls logged yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Card(
                      child: Column(
                        children: [
                          for (final (i, f) in rows.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _FollowupTile(
                              followup: f,
                              onDelete: canLog
                                  ? () => _deleteFollowup(f)
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            if (canClaim || canDelete) ...[
              const SizedBox(height: Spacing.lg),
              Row(
                children: [
                  if (canClaim)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                        onPressed: _edit,
                      ),
                    ),
                  if (canClaim && canDelete) const SizedBox(width: Spacing.sm),
                  if (canDelete)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: status.overdue,
                        ),
                        onPressed: _delete,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Says plainly that the lead is on the books now — the sheet's headline once
/// convert has run.
class _ConvertedBanner extends StatelessWidget {
  const _ConvertedBanner({this.clientName});

  final String? clientName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settled = context.statusColors.settled;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: settled.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: settled.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_outlined, size: 20, color: settled),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              clientName == null
                  ? 'Converted — this lead is a client.'
                  : 'Converted — now a client as $clientName.',
              style: theme.textTheme.bodyMedium?.copyWith(color: settled),
            ),
          ),
        ],
      ),
    );
  }
}

/// One logged call: outcome, who and when in mono, the notes as a sentence,
/// and the next booked date as the aligned figure on the right.
class _FollowupTile extends StatelessWidget {
  const _FollowupTile({required this.followup, this.onDelete});

  final WhatsappFollowup followup;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = followup;

    return ListTile(
      dense: true,
      title: Text(
        FollowupOutcome.labelFor(f.outcome),
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommsMeta(
            [
              Formatting.date(f.callDate),
              if (f.userName != null) f.userName!,
            ].join(' · '),
          ),
          if (f.notes != null) ...[
            const SizedBox(height: 2),
            Text(
              f.notes!,
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (f.nextFollowupDate != null)
            Text(
              '→ ${Formatting.date(f.nextFollowupDate)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Delete this call',
              color: context.statusColors.overdue,
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _LogFollowupForm extends ConsumerStatefulWidget {
  const _LogFollowupForm({required this.contactId, required this.onDone});

  final String contactId;
  final VoidCallback onDone;

  @override
  ConsumerState<_LogFollowupForm> createState() => _LogFollowupFormState();
}

class _LogFollowupFormState extends ConsumerState<_LogFollowupForm> {
  final _notes = TextEditingController();

  FollowupOutcome _outcome = FollowupOutcome.answered;
  DateTime _callDate = DateTime.now();
  DateTime? _nextDate;
  bool _saving = false;
  String? _formError;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool forNext}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: forNext ? (_nextDate ?? now) : _callDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (forNext) {
        _nextDate = picked;
      } else {
        _callDate = picked;
      }
    });
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      await ref
          .read(commsServiceProvider)
          .logWhatsappFollowup(
            widget.contactId,
            callDate: _callDate,
            outcome: _outcome,
            notes: _notes.text.trim(),
            nextFollowupDate: _nextDate,
          );
      ref.invalidate(whatsappFollowupsProvider(widget.contactId));
      // A logged next date moves the contact too, so the due list is stale.
      ref.invalidate(whatsappContactsProvider);
      showCommsMessage(messenger, 'Call logged.');
      widget.onDone();
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_formError != null) ...[
              ErrorBanner(message: _formError!),
              const SizedBox(height: Spacing.md),
            ],
            const CommsFieldLabel('Outcome'),
            const SizedBox(height: Spacing.sm),
            DropdownButtonFormField<FollowupOutcome>(
              initialValue: _outcome,
              isExpanded: true,
              items: [
                for (final o in FollowupOutcome.values)
                  DropdownMenuItem<FollowupOutcome>(
                    value: o,
                    child: Text(o.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _outcome = value);
              },
            ),
            const SizedBox(height: Spacing.md),
            const CommsFieldLabel('Dates'),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _pickDate(forNext: false),
                    child: Text(
                      'Called ${Formatting.date(_callDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _pickDate(forNext: true),
                    child: Text(
                      _nextDate == null
                          ? 'Next call…'
                          : 'Next ${Formatting.date(_nextDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            const CommsFieldLabel('Notes'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              enabled: !_saving,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'What was said',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _saving ? 'Saving…' : 'Save call',
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(
              onPressed: _saving ? null : widget.onDone,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignsView extends ConsumerWidget {
  const _CampaignsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(whatsappCampaignsProvider);

    return CommsAsyncView<List<WhatsappCampaign>>(
      value: campaigns,
      errorTitle: 'Could not load campaigns',
      onRetry: () => ref.invalidate(whatsappCampaignsProvider),
      builder: (context, rows) => rows.isEmpty
          ? const StateMessage(
              icon: Icons.campaign_outlined,
              title: 'No campaigns',
              message: 'Paid WhatsApp campaigns you run appear here.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(whatsappCampaignsProvider.future),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: rows.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) =>
                    _CampaignCard(campaign: rows[index]),
              ),
            ),
    );
  }
}

/// One campaign: name with its budget as the aligned figure, the run dates in
/// mono, and the three figures it is judged on as a rail. Tapping it opens the
/// edit-or-delete pair, when the signed-in user may do either.
class _CampaignCard extends ConsumerWidget {
  const _CampaignCard({required this.campaign});

  final WhatsappCampaign campaign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final c = campaign;
    final canEdit = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappCampaignsUpdate),
    );
    final canDelete = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappCampaignsDelete),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: (canEdit || canDelete)
            ? () =>
                  _actions(context, ref, canEdit: canEdit, canDelete: canDelete)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: Spacing.xs),
                        CommsMeta(
                          [
                            Formatting.date(c.startDate),
                            if (c.endDate != null)
                              'to ${Formatting.date(c.endDate)}',
                          ].join(' '),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Money(c.budget),
                ],
              ),
              const Divider(height: Spacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: 'Leads',
                      child: _count(context, c.leadsCount),
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Converted',
                      child: _count(
                        context,
                        c.convertedCount,
                        color: c.convertedCount > 0 ? status.settled : null,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Per conversion',
                      child: c.costPerConversion == null
                          ? _count(context, null)
                          : Money(
                              c.costPerConversion,
                              scale: MoneyScale.row,
                              showCode: false,
                            ),
                    ),
                  ),
                ],
              ),
              if (c.notes != null) ...[
                const SizedBox(height: Spacing.md),
                Text(
                  c.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _actions(
    BuildContext context,
    WidgetRef ref, {
    required bool canEdit,
    required bool canDelete,
  }) async {
    final scheme = Theme.of(context).colorScheme;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: commsSheetShape,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommsSheetHeader(eyebrow: 'Campaign', title: campaign.name),
              const SizedBox(height: Spacing.md),
              if (canEdit)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit campaign'),
                  onTap: () => Navigator.of(sheetContext).pop('edit'),
                ),
              if (canDelete)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, color: scheme.error),
                  title: Text(
                    'Delete campaign',
                    style: TextStyle(color: scheme.error),
                  ),
                  subtitle: const Text('The leads it produced stay'),
                  onTap: () => Navigator.of(sheetContext).pop('delete'),
                ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted) return;
    if (action == 'edit') {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: commsSheetShape,
        builder: (_) => _CampaignFormSheet(campaign: campaign),
      );
      if (saved == true) ref.invalidate(whatsappCampaignsProvider);
    } else if (action == 'delete') {
      final sure = await _confirmWhatsapp(
        context,
        title: 'Delete the ${campaign.name} campaign?',
        message:
            'The spend and its lead counts stop being tracked. The contacts '
            'it brought in stay where they are.',
        verb: 'Delete',
      );
      if (!sure || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref
            .read(commsServiceProvider)
            .deleteWhatsappCampaign(campaign.id);
        ref.invalidate(whatsappCampaignsProvider);
        showCommsMessage(messenger, 'Campaign deleted.');
      } on ApiException catch (e) {
        showCommsMessage(messenger, e.message, isError: true);
      }
    }
  }

  /// A count typeset like [Money]'s integer part so the three columns sit
  /// at one weight; null renders as a dash.
  static Widget _count(BuildContext context, int? value, {Color? color}) =>
      Text(
        value == null ? '—' : Formatting.integer(value),
        style: TextStyle(
          fontFamily: Type.family,
          fontSize: MoneyScale.row.size,
          fontWeight: FontWeight.w700,
          height: 1,
          fontFeatures: Type.figures,
          color: color ?? Theme.of(context).colorScheme.onSurface,
        ),
      );
}

/// A figure over its eyebrow — one column of an in-card rail.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        child,
        const SizedBox(height: Spacing.xs + 2),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Turn a lead into a billing client.
///
/// `convertToClient` takes either an existing `client_id` or a name to create
/// one with, so this is two modes over one button. Creating prefills from the
/// contact — the name and the number already on the card — because retyping
/// them on a phone is exactly the friction this removes.
class _ConvertContactSheet extends ConsumerStatefulWidget {
  const _ConvertContactSheet({required this.contact});

  final WhatsappContact contact;

  @override
  ConsumerState<_ConvertContactSheet> createState() =>
      _ConvertContactSheetState();
}

class _ConvertContactSheetState extends ConsumerState<_ConvertContactSheet> {
  late final _name = TextEditingController(text: widget.contact.name);
  late final _phone = TextEditingController(text: widget.contact.phone);
  final _email = TextEditingController();

  bool _linkExisting = false;
  String? _clientId;
  String? _clientName;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _pickClient() async {
    final client = await ClientPickerSheet.show(context);
    if (client == null) return;
    setState(() {
      _clientId = client.id;
      _clientName = client.name;
    });
  }

  Future<void> _submit() async {
    if (_linkExisting && _clientId == null) {
      setState(() => _error = 'Choose the client to link this contact to.');
      return;
    }
    if (!_linkExisting && _name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the client’s name.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final converted = await ref
          .read(commsServiceProvider)
          .convertWhatsappContact(
            widget.contact.id,
            clientId: _linkExisting ? _clientId : null,
            clientName: _linkExisting ? null : _name.text.trim(),
            clientEmail: _linkExisting || _email.text.trim().isEmpty
                ? null
                : _email.text.trim(),
            clientPhone: _linkExisting || _phone.text.trim().isEmpty
                ? null
                : _phone.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(converted);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('client_name') ?? e.errorFor('client_id') ?? e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _CommsFormSheet(
      eyebrow: widget.contact.name,
      title: 'Convert to client',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Text(
          'The contact is linked to the new client and moves to the '
          'new-customer stage.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              textStyle: theme.textTheme.labelMedium,
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('New client')),
              ButtonSegment(value: true, label: Text('Existing client')),
            ],
            selected: {_linkExisting},
            onSelectionChanged: _submitting
                ? null
                : (values) => setState(() => _linkExisting = values.first),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (_linkExisting) ...[
          const CommsFieldLabel('Client'),
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_search_outlined, size: 18),
            label: Text(
              _clientName ?? 'Search for a client',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _submitting ? null : _pickClient,
          ),
        ] else ...[
          const CommsFieldLabel('Client name'),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _name,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'The name to bill under',
            ),
          ),
          const SizedBox(height: Spacing.md),
          const CommsFieldLabel('Phone'),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _phone,
            enabled: !_submitting,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '0712 345 678'),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'If another client already holds this number the client is saved '
            'without it, rather than the conversion failing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.md),
          const CommsFieldLabel('Email (optional)'),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _email,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'name@business.co.tz'),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Converting…' : 'Convert to client',
          busy: _submitting,
          icon: Icons.how_to_reg_outlined,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// Add a lead, or correct one already on the board.
///
/// `store` and `update` validate the same fields, so one form serves both.
/// The create response also reports a **client** already holding the number,
/// which is worth saying out loud before someone converts a duplicate.
class _ContactFormSheet extends ConsumerStatefulWidget {
  const _ContactFormSheet({this.contact});

  final WhatsappContact? contact;

  @override
  ConsumerState<_ContactFormSheet> createState() => _ContactFormSheetState();
}

class _ContactFormSheetState extends ConsumerState<_ContactFormSheet> {
  late final _name = TextEditingController(text: widget.contact?.name ?? '');
  late final _phone = TextEditingController(text: widget.contact?.phone ?? '');
  late final _notes = TextEditingController(text: widget.contact?.notes ?? '');

  late WhatsappLabel _label =
      WhatsappLabel.tryParse(widget.contact?.label) ?? WhatsappLabel.lead;
  late WhatsappSource _source =
      WhatsappSource.tryParse(widget.contact?.source) ?? WhatsappSource.direct;
  late bool _important = widget.contact?.isImportant ?? false;
  late String? _campaignId = widget.contact?.campaignId;
  late DateTime? _nextFollowup = widget.contact?.nextFollowupDate;
  late final Set<String> _services = {...?widget.contact?.services};

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.contact != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _toggleService(String service, bool on) {
    setState(() {
      if (on) {
        _services.add(service);
      } else {
        _services.remove(service);
      }
    });
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the contact’s name.');
      return;
    }
    if (_phone.text.trim().isEmpty) {
      setState(() => _error = 'Enter the WhatsApp number.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(commsServiceProvider);
      final notes = _notes.text.trim();
      final contact = widget.contact;
      String message;
      if (contact == null) {
        final created = await service.createWhatsappContact(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          label: _label,
          source: _source,
          isImportant: _important,
          campaignId: _campaignId,
          notes: notes.isEmpty ? null : notes,
          services: _services.toList(),
          nextFollowupDate: _nextFollowup,
        );
        message = created.matchesExistingClient
            ? 'Contact added — that number already belongs to '
                  '${created.existingClientName ?? 'an existing client'}.'
            : 'Contact added.';
      } else {
        await service.updateWhatsappContact(
          contact.id,
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          label: _label,
          source: _source,
          isImportant: _important,
          campaignId: _campaignId,
          notes: notes,
          services: _services.toList(),
          nextFollowupDate: _nextFollowup,
        );
        message = 'Contact updated.';
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      showCommsMessage(messenger, message);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.errorFor('phone') ?? e.errorFor('name') ?? e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = ref.watch(whatsappCampaignsProvider).valueOrNull;

    return _CommsFormSheet(
      eyebrow: 'WhatsApp',
      title: _isEdit ? 'Edit contact' : 'Add a contact',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        const CommsFieldLabel('Name'),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _name,
          enabled: !_submitting,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Who you are talking to'),
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('WhatsApp number'),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _phone,
          enabled: !_submitting,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '0712 345 678'),
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Stage'),
        const SizedBox(height: Spacing.sm),
        DropdownButtonFormField<WhatsappLabel>(
          initialValue: _label,
          isExpanded: true,
          items: [
            for (final option in WhatsappLabel.values)
              DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          onChanged: _submitting
              ? null
              : (value) {
                  if (value != null) setState(() => _label = value);
                },
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Source'),
        const SizedBox(height: Spacing.sm),
        DropdownButtonFormField<WhatsappSource>(
          initialValue: _source,
          isExpanded: true,
          items: [
            for (final option in WhatsappSource.values)
              DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          onChanged: _submitting
              ? null
              : (value) {
                  if (value != null) setState(() => _source = value);
                },
        ),
        if (campaigns != null && campaigns.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          const CommsFieldLabel('Campaign (optional)'),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<String?>(
            initialValue: campaigns.any((c) => c.id == _campaignId)
                ? _campaignId
                : null,
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No campaign'),
              ),
              for (final campaign in campaigns)
                DropdownMenuItem<String?>(
                  value: campaign.id,
                  child: Text(campaign.name),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() => _campaignId = value),
          ),
        ],
        const SizedBox(height: Spacing.md),
        _ServicesField(
          selected: _services,
          enabled: !_submitting,
          onToggle: _toggleService,
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Next call (optional)'),
        const SizedBox(height: Spacing.sm),
        OutlinedButton(
          onPressed: _submitting
              ? null
              : () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _nextFollowup ?? now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 2),
                  );
                  if (picked != null) setState(() => _nextFollowup = picked);
                },
          child: Text(
            _nextFollowup == null
                ? 'Choose a date'
                : Formatting.date(_nextFollowup),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const CommsFieldLabel('Flag as important'),
          value: _important,
          onChanged: _submitting
              ? null
              : (value) => setState(() => _important = value),
        ),
        const SizedBox(height: Spacing.sm),
        const CommsFieldLabel('Notes'),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _notes,
          enabled: !_submitting,
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(hintText: 'What they are after'),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting
              ? 'Saving…'
              : (_isEdit ? 'Save changes' : 'Add contact'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// "Services interested in" — the same tenant-defined reference list
/// `_ServicesDiscussedField` in field_marketing_screen.dart reads for a field
/// visit, since a WhatsApp lead and a visit tag against one shared list of
/// what the business sells.
class _ServicesField extends ConsumerWidget {
  const _ServicesField({
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final Set<String> selected;
  final bool enabled;
  final void Function(String service, bool on) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(marketingServicesProvider);
    // Same offline fallback as the field-visit picker: only reached when the
    // reference list has never once loaded.
    final names = servicesAsync.when(
      loading: () => FieldServices.values,
      error: (error, _) => FieldServices.values,
      data: (items) => items.isEmpty
          ? FieldServices.values
          : [for (final item in items) item.name],
    );
    final canManage = ref.watch(
      commsPermissionProvider(CrmPermissions.marketingServicesRead),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CommsFieldLabel('Services interested in'),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final service in names)
              FilterChip(
                label: Text(service.toUpperCase()),
                selected: selected.contains(service),
                showCheckmark: false,
                onSelected: !enabled ? null : (on) => onToggle(service, on),
              ),
          ],
        ),
        if (canManage) ...[
          const SizedBox(height: Spacing.xs),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MarketingServicesScreen(),
              ),
            ),
            child: Text(
              '+ Manage services',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Create or correct a paid campaign — the spend the lead counts are judged
/// against.
class _CampaignFormSheet extends ConsumerStatefulWidget {
  const _CampaignFormSheet({this.campaign});

  final WhatsappCampaign? campaign;

  @override
  ConsumerState<_CampaignFormSheet> createState() => _CampaignFormSheetState();
}

class _CampaignFormSheetState extends ConsumerState<_CampaignFormSheet> {
  late final _name = TextEditingController(text: widget.campaign?.name ?? '');
  late final _budget = TextEditingController(
    text: widget.campaign == null
        ? ''
        : Formatting.amount(widget.campaign!.budget),
  );
  late final _notes = TextEditingController(text: widget.campaign?.notes ?? '');

  late DateTime _startDate = widget.campaign?.startDate ?? DateTime.now();
  late DateTime? _endDate = widget.campaign?.endDate;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.campaign != null;

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool end}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: end ? (_endDate ?? _startDate) : _startDate,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        _endDate = picked;
      } else {
        _startDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name the campaign.');
      return;
    }
    // `budget` is required and numeric server-side; an empty box means zero
    // spend so far, which is a legitimate answer on day one.
    final budget = double.tryParse(
      _budget.text.trim().replaceAll(',', '').isEmpty
          ? '0'
          : _budget.text.trim().replaceAll(',', ''),
    );
    if (budget == null || budget < 0) {
      setState(() => _error = 'Enter the spend as a number.');
      return;
    }
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      setState(() => _error = 'The end date cannot fall before the start.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(commsServiceProvider);
      final notes = _notes.text.trim();
      final campaign = widget.campaign;
      if (campaign == null) {
        await service.createWhatsappCampaign(
          name: _name.text.trim(),
          startDate: _startDate,
          budget: budget,
          endDate: _endDate,
          notes: notes.isEmpty ? null : notes,
        );
      } else {
        await service.updateWhatsappCampaign(
          campaign.id,
          name: _name.text.trim(),
          startDate: _startDate,
          budget: budget,
          endDate: _endDate,
          notes: notes,
        );
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      showCommsMessage(
        messenger,
        _isEdit ? 'Campaign updated.' : 'Campaign created.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => _CommsFormSheet(
    eyebrow: 'WhatsApp',
    title: _isEdit ? 'Edit campaign' : 'New campaign',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      const CommsFieldLabel('Campaign name'),
      const SizedBox(height: Spacing.sm),
      TextField(
        controller: _name,
        enabled: !_submitting,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'What you are running'),
      ),
      const SizedBox(height: Spacing.md),
      const CommsFieldLabel('Dates'),
      const SizedBox(height: Spacing.sm),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting ? null : () => _pick(end: false),
              child: Text(
                'From ${Formatting.date(_startDate)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting ? null : () => _pick(end: true),
              child: Text(
                _endDate == null
                    ? 'Open-ended'
                    : 'To ${Formatting.date(_endDate)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: Spacing.md),
      CommsFieldLabel('Spend (${Formatting.tenantCurrency})'),
      const SizedBox(height: Spacing.sm),
      TextField(
        controller: _budget,
        enabled: !_submitting,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: '0.00'),
      ),
      const SizedBox(height: Spacing.md),
      const CommsFieldLabel('Notes'),
      const SizedBox(height: Spacing.sm),
      TextField(
        controller: _notes,
        enabled: !_submitting,
        minLines: 2,
        maxLines: 4,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(hintText: 'Audience, creative, aim'),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _submitting
            ? 'Saving…'
            : (_isEdit ? 'Save changes' : 'Create campaign'),
        busy: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
    ],
  );
}

/// The body every comms form sheet shares: the header, room for the keyboard,
/// and a cap so a long form still shows the drag handle.
class _CommsFormSheet extends StatelessWidget {
  const _CommsFormSheet({
    required this.title,
    required this.children,
    this.eyebrow,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.9,
    ),
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        Spacing.lg + sheetBottomInset(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CommsSheetHeader(eyebrow: eyebrow, title: title),
          const SizedBox(height: Spacing.lg),
          ...children,
        ],
      ),
    ),
  );
}

/// A confirmation with the verb on the button rather than "OK". Destructive
/// by default — the only unprompted action here is bulk claim.
Future<bool> _confirmWhatsapp(
  BuildContext context, {
  required String title,
  required String message,
  required String verb,
  bool destructive = true,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(verb),
        ),
      ],
    ),
  );
  return sure ?? false;
}

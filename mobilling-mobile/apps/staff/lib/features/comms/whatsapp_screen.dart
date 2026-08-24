import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

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
    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Engagement', title: 'WhatsApp'),
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<WhatsappContact> _visible(List<WhatsappContact> all) {
    final query = _search.text.trim().toLowerCase();
    var rows = widget.dueOnly ? all.where((c) => c.isFollowupDue) : all;

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

    return Column(
      children: [
        if (!widget.dueOnly) ...[
          const _StatsStrip(),
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

  Future<void> _claim() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(commsServiceProvider)
          .claimWhatsappContact(widget.contact.id);
      ref.invalidate(whatsappContactsProvider);
      ref.invalidate(whatsappStatsProvider);
      showCommsMessage(messenger, 'Contact claimed.');
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }

  Future<void> _openWhatsapp() async {
    // wa.me wants digits only; stored numbers carry spaces, plus signs and
    // dashes depending on who typed them in.
    final digits = widget.contact.phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    await launchUrl(
      Uri.parse('https://wa.me/$digits'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final theme = Theme.of(context);
    final followups = ref.watch(whatsappFollowupsProvider(contact.id));
    final canLog = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappContactsLog),
    );
    final canClaim = ref.watch(
      commsPermissionProvider(CommsPermissions.whatsappContactsUpdate),
    );

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
          Spacing.lg + MediaQuery.of(context).viewInsets.bottom,
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
                            _FollowupTile(followup: f),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One logged call: outcome, who and when in mono, the notes as a sentence,
/// and the next booked date as the aligned figure on the right.
class _FollowupTile extends StatelessWidget {
  const _FollowupTile({required this.followup});

  final WhatsappFollowup followup;

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
      trailing: f.nextFollowupDate == null
          ? null
          : Text(
              '→ ${Formatting.date(f.nextFollowupDate)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
              message: 'Paid WhatsApp campaigns are created on the web app.',
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
/// mono, and the three figures it is judged on as a rail.
class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign});

  final WhatsappCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final c = campaign;

    return Card(
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
    );
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

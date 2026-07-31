import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'comms_providers.dart';
import 'comms_ui.dart';

/// Bumped after a successful send so the history tab reloads.
final StateProvider<int> broadcastsRefreshProvider =
    StateProvider<int>((ref) => 0);

/// Mass email/SMS to clients.
///
/// The compose form is deliberately narrow: `BroadcastController::send`
/// accepts a channel, the bodies for that channel, and an optional
/// `client_ids` allowlist. Everything else about who receives it is decided
/// server-side (clients are filtered to those with a usable address), so there
/// is nothing else worth asking the user for.
class BroadcastScreen extends StatelessWidget {
  const BroadcastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Broadcast'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Compose'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ComposeView(), _BroadcastHistoryView()],
        ),
      ),
    );
  }
}

/// The same starting points the web compose screen offers, so a notice sent
/// from a phone reads like one sent from a desk.
const _templates = <String, ({String label, String subject, String body, String sms})>{
  'maintenance': (
    label: 'Scheduled maintenance',
    subject: 'Scheduled Maintenance Notice',
    body: 'Dear Client,\n\n'
        'We will be performing scheduled maintenance on [date] from '
        '[start time] to [end time].\n\n'
        'During this period, our services may be temporarily unavailable. '
        'We apologise for any inconvenience.\n\n'
        'Thank you for your patience.',
    sms: 'Maintenance on [date] [start]-[end]. Services may be briefly '
        'unavailable. We apologise for any inconvenience.',
  ),
  'service_update': (
    label: 'Service update',
    subject: 'Service Update',
    body: 'Dear Client,\n\n'
        'We are pleased to inform you about an important update to our '
        'services.\n\n[Describe the update here]\n\n'
        'If you have any questions, please do not hesitate to contact us.\n\n'
        'Best regards.',
    sms: 'Service update: [brief description]. Contact us for details.',
  ),
  'unavailability': (
    label: 'Service unavailability',
    subject: 'Service Unavailability Notice',
    body: 'Dear Client,\n\n'
        'We regret to inform you that our services will be unavailable on '
        '[date] due to [reason].\n\n'
        'We expect to resume normal operations by [time/date]. We apologise '
        'for any inconvenience caused.\n\nThank you for your understanding.',
    sms: 'Our services will be unavailable on [date] due to [reason]. '
        'Normal operations resume by [time].',
  ),
  'holiday': (
    label: 'Holiday notice',
    subject: 'Holiday Notice',
    body: 'Dear Client,\n\n'
        'Please note that our offices will be closed on [date(s)] for '
        '[holiday name].\n\n'
        'We will resume normal business hours on [return date].\n\n'
        'Wishing you a wonderful holiday!',
    sms: 'Our offices will be closed [date(s)] for [holiday]. We resume on '
        '[return date].',
  ),
  'general': (
    label: 'General announcement',
    subject: 'Important Announcement',
    body: 'Dear Client,\n\n'
        'We would like to bring the following to your attention:\n\n'
        '[Your announcement here]\n\n'
        'Please feel free to reach out if you have any questions.\n\n'
        'Best regards.',
    sms: '[Your announcement here]. Contact us for more info.',
  ),
};

class _ComposeView extends ConsumerStatefulWidget {
  const _ComposeView();

  @override
  ConsumerState<_ComposeView> createState() => _ComposeViewState();
}

class _ComposeViewState extends ConsumerState<_ComposeView> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _smsBody = TextEditingController();

  BroadcastChannel _channel = BroadcastChannel.email;

  /// Chosen recipients. Empty means "no allowlist" — the API then targets every
  /// client with a usable address, which is a very different blast radius, so
  /// the distinction is surfaced in the form and again in the confirmation.
  final Map<String, String> _recipients = {};

  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    _smsBody.dispose();
    super.dispose();
  }

  void _applyTemplate(String key) {
    final template = _templates[key];
    if (template == null) return;
    setState(() {
      _subject.text = template.subject;
      _body.text = template.body;
      _smsBody.text = template.sms;
    });
  }

  Future<void> _pickRecipients() async {
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RecipientPicker(selected: _recipients),
    );
    if (picked != null) {
      setState(() {
        _recipients
          ..clear()
          ..addAll(picked);
      });
    }
  }

  Future<bool> _confirm() async {
    final targeted = _recipients.isNotEmpty;
    final channelWording = switch (_channel) {
      BroadcastChannel.email => 'saved email address',
      BroadcastChannel.sms => 'saved phone number',
      BroadcastChannel.both => 'saved email address or phone number',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(targeted
            ? 'Send to ${_recipients.length} '
                'client${_recipients.length == 1 ? '' : 's'}?'
            : 'Send to every client?'),
        content: Text(
          targeted
              ? 'Only the clients you selected will receive this, and only '
                  'those with a $channelWording. It cannot be recalled.'
              : 'This goes to all clients with a $channelWording. '
                  'It cannot be recalled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _send() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!await _confirm()) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final result = await ref.read(commsServiceProvider).sendBroadcast(
            channel: _channel,
            subject: _subject.text.trim(),
            body: _body.text.trim(),
            smsBody: _smsBody.text.trim(),
            clientIds: _recipients.keys.toList(),
          );
      showCommsMessage(
        messenger,
        '${result.sentCount} of ${result.totalRecipients} delivered'
        '${result.failedCount > 0 ? ', ${result.failedCount} failed' : ''}.',
        isError: result.sentCount == 0 && result.totalRecipients > 0,
      );
      _subject.clear();
      _body.clear();
      _smsBody.clear();
      _recipients.clear();
      ref.read(broadcastsRefreshProvider.notifier).state++;
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend =
        ref.watch(commsPermissionProvider(CommsPermissions.broadcast));

    if (!canSend) {
      return const StateMessage(
        icon: Icons.lock_outline,
        title: 'Viewing only',
        message: 'Your role cannot send broadcasts.',
      );
    }

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<BroadcastChannel>(
              showSelectedIcon: false,
              segments: [
                for (final c in BroadcastChannel.values)
                  ButtonSegment<BroadcastChannel>(
                      value: c, label: Text(c.label)),
              ],
              selected: {_channel},
              onSelectionChanged: (values) =>
                  setState(() => _channel = values.first),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Card(
            child: ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text(_recipients.isEmpty
                  ? 'All clients'
                  : '${_recipients.length} client'
                      '${_recipients.length == 1 ? '' : 's'} selected'),
              subtitle: Text(
                _recipients.isEmpty
                    ? 'Everyone with a usable address on this channel'
                    : _recipients.values.take(3).join(', ') +
                        (_recipients.length > 3
                            ? ' +${_recipients.length - 3} more'
                            : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickRecipients,
            ),
          ),
          const SizedBox(height: Spacing.md),
          DropdownButtonFormField<String>(
            initialValue: null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Start from a template',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final entry in _templates.entries)
                DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) _applyTemplate(value);
            },
          ),
          if (_channel.includesEmail) ...[
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _subject,
              maxLength: 255,
              decoration: const InputDecoration(
                labelText: 'Email subject',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'A subject is required for email.'
                  : null,
            ),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _body,
              minLines: 6,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Email message',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'An email message is required.'
                  : null,
            ),
          ],
          if (_channel.includesSms) ...[
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _smsBody,
              minLines: 3,
              maxLines: 5,
              // 160 is the server's cap, not a soft suggestion — the counter
              // has to be visible while typing.
              maxLength: 160,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'SMS message',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'An SMS message is required.'
                  : null,
            ),
          ],
          const SizedBox(height: Spacing.md),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 18),
            label: const Text('Send broadcast'),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Clients without an address for the chosen channel are skipped '
            'server-side. Sending is not queued — keep the app open until the '
            'tally comes back.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }
}

/// Optional recipient allowlist for a broadcast.
///
/// Backed by `/clients`, which is paginated and searchable — the web picker
/// loads 500 clients in one go and filters in the browser, which is not a
/// trade a phone should make. Selections survive searching and paging because
/// they are held as id -> name, not as indexes into the loaded page.
class _RecipientPicker extends ConsumerStatefulWidget {
  const _RecipientPicker({required this.selected});

  final Map<String, String> selected;

  @override
  ConsumerState<_RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends ConsumerState<_RecipientPicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _chosen = <String, String>{};
  final _loaded = <StaffClient>[];

  Paginated<StaffClient>? _page;
  bool _loading = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _chosen.addAll(widget.selected);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    final next = reset ? 1 : _page?.nextPage;
    if (next == null) return;

    setState(() {
      _loading = true;
      if (reset) _error = null;
    });
    try {
      final page = await ref.read(staffServiceProvider).clients(
            search: _search.text.trim().isEmpty ? null : _search.text.trim(),
            page: next,
            perPage: 50,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _loaded.clear();
        _loaded.addAll(page.items);
        _page = page;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text('Recipients',
                      style: theme.textTheme.titleMedium),
                ),
                if (_chosen.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_chosen.clear),
                    child: const Text('All clients'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(reset: true),
              decoration: InputDecoration(
                hintText: 'Search clients',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  tooltip: 'Search',
                  onPressed: () => _load(reset: true),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: ErrorBanner(
                message: _error!.message,
                onRetry: () => _load(reset: true),
              ),
            ),
          Flexible(
            child: (_loaded.isEmpty && _loading)
                ? const Padding(
                    padding: EdgeInsets.all(Spacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    itemCount: _loaded.length + (_loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _loaded.length) {
                        return const Padding(
                          padding: EdgeInsets.all(Spacing.md),
                          child: Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final client = _loaded[index];
                      return CheckboxListTile(
                        dense: true,
                        value: _chosen.containsKey(client.id),
                        title: Text(client.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            if (client.email != null) client.email!,
                            if (client.phone != null) client.phone!,
                            if (client.email == null && client.phone == null)
                              'No email or phone — will be skipped',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: (checked) => setState(() {
                          if (checked ?? false) {
                            _chosen[client.id] = client.name;
                          } else {
                            _chosen.remove(client.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.md + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _chosen.isEmpty
                        ? 'All clients'
                        : '${_chosen.length} selected',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop<Map<String, String>>(_chosen),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BroadcastHistoryView extends ConsumerStatefulWidget {
  const _BroadcastHistoryView();

  @override
  ConsumerState<_BroadcastHistoryView> createState() =>
      _BroadcastHistoryViewState();
}

class _BroadcastHistoryViewState extends ConsumerState<_BroadcastHistoryView> {
  final _list = GlobalKey<PagedListViewState<Broadcast>>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    ref.listen<int>(broadcastsRefreshProvider,
        (previous, next) => _list.currentState?.reload());

    return PagedListView<Broadcast>(
      key: _list,
      fetch: (page) => ref.read(commsServiceProvider).broadcasts(page: page),
      emptyIcon: Icons.campaign_outlined,
      emptyTitle: 'Nothing sent yet',
      itemBuilder: (context, broadcast) => Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      broadcast.subject ?? broadcast.smsBody ?? 'Broadcast',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  StatusChip(broadcast.deliveryStatus, dense: true),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                [
                  broadcast.channel.label,
                  '${broadcast.sentCount}/${broadcast.totalRecipients} sent',
                  if (broadcast.failedCount > 0)
                    '${broadcast.failedCount} failed',
                  if (broadcast.wasTargeted) 'selected clients',
                  if (broadcast.senderName != null) broadcast.senderName!,
                  Formatting.dateTime(broadcast.createdAt),
                ].join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (broadcast.body != null || broadcast.smsBody != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  htmlToPlainText(broadcast.body ?? broadcast.smsBody!),
                  style: theme.textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

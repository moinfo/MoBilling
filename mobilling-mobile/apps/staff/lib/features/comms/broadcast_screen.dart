import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'comms_providers.dart';
import 'comms_ui.dart';

/// Bumped after a successful send so the history tab reloads.
final StateProvider<int> broadcastsRefreshProvider = StateProvider<int>(
  (ref) => 0,
);

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
        appBar: const ShellTopBar(
          eyebrow: 'Communications',
          title: 'Broadcast',
          bottom: InkTabBar(tabs: ['Compose', 'Sent']),
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
const _templates =
    <String, ({String label, String subject, String body, String sms})>{
      'maintenance': (
        label: 'Scheduled maintenance',
        subject: 'Scheduled Maintenance Notice',
        body:
            'Dear Client,\n\n'
            'We will be performing scheduled maintenance on [date] from '
            '[start time] to [end time].\n\n'
            'During this period, our services may be temporarily unavailable. '
            'We apologise for any inconvenience.\n\n'
            'Thank you for your patience.',
        sms:
            'Maintenance on [date] [start]-[end]. Services may be briefly '
            'unavailable. We apologise for any inconvenience.',
      ),
      'service_update': (
        label: 'Service update',
        subject: 'Service Update',
        body:
            'Dear Client,\n\n'
            'We are pleased to inform you about an important update to our '
            'services.\n\n[Describe the update here]\n\n'
            'If you have any questions, please do not hesitate to contact us.\n\n'
            'Best regards.',
        sms: 'Service update: [brief description]. Contact us for details.',
      ),
      'unavailability': (
        label: 'Service unavailability',
        subject: 'Service Unavailability Notice',
        body:
            'Dear Client,\n\n'
            'We regret to inform you that our services will be unavailable on '
            '[date] due to [reason].\n\n'
            'We expect to resume normal operations by [time/date]. We apologise '
            'for any inconvenience caused.\n\nThank you for your understanding.',
        sms:
            'Our services will be unavailable on [date] due to [reason]. '
            'Normal operations resume by [time].',
      ),
      'holiday': (
        label: 'Holiday notice',
        subject: 'Holiday Notice',
        body:
            'Dear Client,\n\n'
            'Please note that our offices will be closed on [date(s)] for '
            '[holiday name].\n\n'
            'We will resume normal business hours on [return date].\n\n'
            'Wishing you a wonderful holiday!',
        sms:
            'Our offices will be closed [date(s)] for [holiday]. We resume on '
            '[return date].',
      ),
      'general': (
        label: 'General announcement',
        subject: 'Important Announcement',
        body:
            'Dear Client,\n\n'
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
  final _whatsappBody = TextEditingController();

  BroadcastChannel _channel = BroadcastChannel.email;

  /// Chosen recipients. Empty means "no allowlist" — the API then targets every
  /// client with a usable address, which is a very different blast radius, so
  /// the distinction is surfaced in the form and again in the confirmation.
  final Map<String, String> _recipients = {};

  bool _sending = false;

  /// A rejected send, shown above the form rather than in a snackbar so it is
  /// still there when the reader looks up from the field they were editing.
  String? _formError;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    _smsBody.dispose();
    _whatsappBody.dispose();
    super.dispose();
  }

  void _applyTemplate(String key) {
    final template = _templates[key];
    if (template == null) return;
    setState(() {
      _subject.text = template.subject;
      _body.text = template.body;
      _smsBody.text = template.sms;
      _whatsappBody.text = template.body;
    });
  }

  Future<void> _pickRecipients() async {
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: commsSheetShape,
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
      BroadcastChannel.whatsapp => 'saved phone number',
      BroadcastChannel.both => 'saved email address or phone number',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          targeted
              ? 'Send to ${_recipients.length} '
                    'client${_recipients.length == 1 ? '' : 's'}?'
              : 'Send to every client?',
        ),
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
            child: const Text('Send broadcast'),
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

    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _sending = true;
      _formError = null;
    });
    try {
      final result = await ref
          .read(commsServiceProvider)
          .sendBroadcast(
            channel: _channel,
            subject: _subject.text.trim(),
            body: _body.text.trim(),
            smsBody: _smsBody.text.trim(),
            whatsappBody: _whatsappBody.text.trim(),
            clientIds: _recipients.keys.toList(),
          );
      showCommsMessage(messenger, result.message);
      _subject.clear();
      _body.clear();
      _smsBody.clear();
      _whatsappBody.clear();
      _recipients.clear();
      ref.read(broadcastsRefreshProvider.notifier).state++;
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend = ref.watch(
      commsPermissionProvider(CommsPermissions.broadcast),
    );

    if (!canSend) {
      return const StateMessage(
        icon: Icons.lock_outline,
        title: 'Viewing only',
        message: 'Your role cannot send broadcasts.',
      );
    }

    final recipientSummary = _recipients.isEmpty
        ? 'Everyone with a usable address on this channel'
        : _recipients.values.take(3).join(', ') +
              (_recipients.length > 3
                  ? ' +${_recipients.length - 3} more'
                  : '');

    return Form(
      key: _form,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (_formError != null) ...[
            ErrorBanner(message: _formError!),
            const SizedBox(height: Spacing.md),
          ],
          const CommsFieldLabel('Channel'),
          const SizedBox(height: Spacing.sm),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<BroadcastChannel>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                textStyle: theme.textTheme.labelMedium,
              ),
              segments: [
                for (final c in BroadcastChannel.values)
                  ButtonSegment<BroadcastChannel>(
                    value: c,
                    label: Text(c.label),
                  ),
              ],
              selected: {_channel},
              onSelectionChanged: (values) =>
                  setState(() => _channel = values.first),
            ),
          ),
          const SizedBox(height: Spacing.md),
          const CommsFieldLabel('Recipients'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: ListTile(
              title: Text(
                _recipients.isEmpty
                    ? 'All clients'
                    : '${_recipients.length} client'
                          '${_recipients.length == 1 ? '' : 's'} selected',
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text(
                recipientSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickRecipients,
            ),
          ),
          const SizedBox(height: Spacing.md),
          const CommsFieldLabel('Start from a template'),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<String>(
            initialValue: null,
            isExpanded: true,
            decoration: const InputDecoration(hintText: 'Choose a template'),
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
            const CommsFieldLabel('Email subject'),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _subject,
              maxLength: 255,
              enabled: !_sending,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'What the email is about',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter a subject for the email.'
                  : null,
            ),
            const SizedBox(height: Spacing.md),
            const CommsFieldLabel('Email message'),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _body,
              minLines: 6,
              maxLines: 12,
              enabled: !_sending,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Dear Client, …',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter the email message.'
                  : null,
            ),
          ],
          if (_channel.includesSms) ...[
            const SizedBox(height: Spacing.md),
            const CommsFieldLabel('SMS message'),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _smsBody,
              minLines: 3,
              maxLines: 5,
              enabled: !_sending,
              // 160 is the server's cap, not a soft suggestion — the counter
              // has to be visible while typing.
              maxLength: 160,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Up to 160 characters',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter the SMS message.'
                  : null,
            ),
          ],
          if (_channel.includesWhatsapp) ...[
            const SizedBox(height: Spacing.md),
            const CommsFieldLabel('WhatsApp message'),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _whatsappBody,
              minLines: 6,
              maxLines: 12,
              enabled: !_sending,
              maxLength: 4096,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Dear Client, …',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter the WhatsApp message.'
                  : null,
            ),
          ],
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: _sending ? 'Sending…' : 'Send broadcast',
            icon: Icons.send_rounded,
            busy: _sending,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Clients without an address for the chosen channel are skipped '
            'server-side. Sending happens in the background — check the '
            'Sent tab for live progress.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
      final page = await ref
          .read(staffServiceProvider)
          .clients(
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
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.md,
            ),
            child: CommsSheetHeader(
              eyebrow: 'Broadcast',
              title: 'Recipients',
              trailing: _chosen.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () => setState(_chosen.clear),
                      child: const Text('Clear selection'),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(reset: true),
              decoration: InputDecoration(
                hintText: 'Search clients',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  tooltip: 'Search',
                  onPressed: () => _load(reset: true),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                0,
              ),
              child: ErrorBanner(
                message: _error!.message,
                onRetry: () => _load(reset: true),
              ),
            ),
          const SizedBox(height: Spacing.sm),
          Flexible(
            child: (_loaded.isEmpty && _loading)
                ? const Padding(
                    padding: EdgeInsets.all(Spacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                    itemCount: _loaded.length + (_loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _loaded.length) {
                        return const Padding(
                          padding: EdgeInsets.all(Spacing.md),
                          child: Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final client = _loaded[index];
                      final unreachable =
                          client.email == null && client.phone == null;
                      return CheckboxListTile(
                        dense: true,
                        value: _chosen.containsKey(client.id),
                        title: Text(
                          client.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                        subtitle: unreachable
                            ? Text(
                                'No email or phone — will be skipped',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : CommsMeta(
                                [
                                  if (client.email != null) client.email!,
                                  if (client.phone != null) client.phone!,
                                ].join(' · '),
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
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.lg + sheetBottomInset(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (_chosen.isEmpty
                          ? 'All clients'
                          : '${_chosen.length} selected')
                      .toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                PrimaryButton(
                  label: _chosen.isEmpty
                      ? 'Use all clients'
                      : 'Use these recipients',
                  onPressed: () =>
                      Navigator.of(context).pop<Map<String, String>>(_chosen),
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

  /// Live progress: while a fetched page still has a broadcast whose send
  /// hasn't settled, reload again in a few seconds so the tally catches up.
  /// [PagedListView] has no hook of its own for "a page just loaded", so this
  /// wraps the fetcher passed to it instead of touching its public API.
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<Paginated<Broadcast>> _fetch(int page) async {
    final result = await ref.read(commsServiceProvider).broadcasts(page: page);
    _scheduleNextPollIfNeeded(result);
    return result;
  }

  void _scheduleNextPollIfNeeded(Paginated<Broadcast> page) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!page.items.any((b) => b.inProgress)) return;

    _pollTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _list.currentState?.reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      broadcastsRefreshProvider,
      (previous, next) => _list.currentState?.reload(),
    );

    return PagedListView<Broadcast>(
      key: _list,
      fetch: _fetch,
      emptyIcon: Icons.campaign_outlined,
      emptyTitle: 'Nothing sent yet',
      emptyMessage: 'Broadcasts you send will be listed here.',
      itemBuilder: (context, broadcast) => _BroadcastCard(broadcast: broadcast),
    );
  }
}

/// One sent broadcast: subject, status beside its metadata, the delivery
/// tally as the aligned figure on the right, and a preview of the body.
///
/// While [Broadcast.inProgress] the tally is replaced by a small spinner —
/// the send is still running server-side (`SendBroadcastJob`) and the counts
/// have not settled yet, so showing `0/40` would read as a failure rather
/// than as work in progress.
class _BroadcastCard extends ConsumerWidget {
  const _BroadcastCard({required this.broadcast});

  final Broadcast broadcast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final preview = broadcast.body ?? broadcast.smsBody;

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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              broadcast.subject ??
                                  broadcast.smsBody ??
                                  'Broadcast',
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (broadcast.isRetry) ...[
                            const SizedBox(width: Spacing.sm),
                            CommsChip(
                              label: 'Retry',
                              color: theme.colorScheme.tertiary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: Spacing.xs),
                      Row(
                        children: [
                          StatusChip(broadcast.deliveryStatus, dense: true),
                          const SizedBox(width: Spacing.sm),
                          Flexible(
                            child: CommsMeta(
                              [
                                broadcast.channel.label,
                                if (broadcast.wasTargeted) 'selected clients',
                                if (broadcast.senderName != null)
                                  broadcast.senderName!,
                                Formatting.dateTime(broadcast.createdAt),
                              ].join(' · '),
                            ),
                          ),
                          if (!broadcast.inProgress &&
                              broadcast.failedCount > 0) ...[
                            const SizedBox(width: Spacing.sm),
                            InkWell(
                              onTap: () =>
                                  _showRecipients(context, ref, sent: false),
                              child: Text(
                                '${broadcast.failedCount} failed',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: status.overdue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                broadcast.inProgress
                    ? const _SendingIndicator()
                    : _Tally(
                        sent: broadcast.sentCount,
                        total: broadcast.totalRecipients,
                        color: switch (broadcast.deliveryStatus) {
                          'failed' => status.overdue,
                          'partial' => status.attention,
                          _ => null,
                        },
                        onTap: broadcast.sentCount == 0
                            ? null
                            : () => _showRecipients(context, ref, sent: true),
                      ),
              ],
            ),
            if (preview != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                htmlToPlainText(preview),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (broadcast.canResendFailed) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                    ),
                  ),
                  icon: const Icon(Icons.replay, size: 16),
                  label: Text(
                    'Resend to ${broadcast.failedCount} failed',
                  ),
                  onPressed: () => _resendFailed(context, ref),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRecipients(
    BuildContext context,
    WidgetRef ref, {
    required bool sent,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: commsSheetShape,
    builder: (context) =>
        _BroadcastRecipientsSheet(broadcastId: broadcast.id, sent: sent),
  );

  Future<void> _resendFailed(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(commsServiceProvider)
          .resendFailedBroadcast(broadcast.id);
      showCommsMessage(messenger, result.message);
      ref.read(broadcastsRefreshProvider.notifier).state++;
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }
}

/// The right-hand column while a send is still running: a small spinner and
/// "sending…", mirroring the web's `Loader size="xs"` in the Failed column.
class _SendingIndicator extends StatelessWidget {
  const _SendingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          'sending…',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// `12/40` over a SENT eyebrow — the list's right-hand column. Tappable once
/// there is somebody to show, opening the sent-recipients sheet.
class _Tally extends StatelessWidget {
  const _Tally({
    required this.sent,
    required this.total,
    this.color,
    this.onTap,
  });

  final int sent;
  final int total;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${Formatting.integer(sent)}/${Formatting.integer(total)}',
          style: TextStyle(
            fontFamily: Type.family,
            fontSize: MoneyScale.row.size,
            fontWeight: FontWeight.w700,
            height: 1,
            fontFeatures: Type.figures,
            color: color ?? theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          'SENT',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(Spacing.xs), child: content),
    );
  }
}

/// Who did or didn't get one broadcast — `GET /broadcasts/{id}/recipients`,
/// opened from the sent count or the failed count on [_BroadcastCard].
class _BroadcastRecipientsSheet extends ConsumerStatefulWidget {
  const _BroadcastRecipientsSheet({
    required this.broadcastId,
    required this.sent,
  });

  final String broadcastId;
  final bool sent;

  @override
  ConsumerState<_BroadcastRecipientsSheet> createState() =>
      _BroadcastRecipientsSheetState();
}

class _BroadcastRecipientsSheetState
    extends ConsumerState<_BroadcastRecipientsSheet> {
  late final Future<List<BroadcastRecipient>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(commsServiceProvider)
        .broadcastRecipients(widget.broadcastId, sent: widget.sent);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.md,
            ),
            child: CommsSheetHeader(
              eyebrow: 'Broadcast',
              title: widget.sent ? 'Sent to' : 'Failed for',
            ),
          ),
          Flexible(
            child: FutureBuilder<List<BroadcastRecipient>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(Spacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: ErrorBanner(
                      message: commsErrorText(snapshot.error!),
                    ),
                  );
                }

                final recipients = snapshot.data ?? const [];
                if (recipients.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Center(
                      child: Text(
                        widget.sent ? 'Nobody yet.' : 'No failures.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg,
                    vertical: Spacing.sm,
                  ),
                  itemCount: recipients.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final r = recipients[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: r.reason != null
                          ? Text(
                              r.reason!,
                              maxLines: 2,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            )
                          : CommsMeta(
                              [
                                if (r.email != null) r.email!,
                                if (r.phone != null) r.phone!,
                              ].join(' · '),
                            ),
                    );
                  },
                );
              },
            ),
          ),
          SizedBox(height: sheetBottomInset(context) + Spacing.md),
        ],
      ),
    );
  }
}

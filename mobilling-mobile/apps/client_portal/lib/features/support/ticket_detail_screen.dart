import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/share_pdf.dart';

/// A ticket's reply thread, chat-style, with a composer pinned below.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() =>
      _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  final _message = TextEditingController();
  final List<PlatformFile> _attachments = [];
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    setState(() {
      _attachments.addAll(result.files.where((f) => f.path != null));
      // Backend caps at 5 per message.
      while (_attachments.length > 5) {
        _attachments.removeLast();
      }
    });
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await ref.read(portalServiceProvider).replyTicket(
            widget.ticketId,
            message: text,
            attachmentPaths:
                _attachments.map((f) => f.path!).toList(growable: false),
          );
      _message.clear();
      _attachments.clear();
      ref.invalidate(ticketProvider(widget.ticketId));
      ref.invalidate(ticketsProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this ticket?'),
        content: const Text(
            'You can reopen it any time by sending another reply.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close ticket')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(portalServiceProvider).closeTicket(widget.ticketId);
      ref.invalidate(ticketProvider(widget.ticketId));
      ref.invalidate(ticketsProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(ticketProvider(widget.ticketId));

    return Scaffold(
      appBar: AppBar(
        title: Text(ticket.valueOrNull?.ticketNumber ?? 'Ticket'),
        actions: [
          if (ticket.valueOrNull != null && !ticket.value!.isClosed)
            IconButton(
              icon: const Icon(Icons.task_alt_outlined),
              tooltip: 'Close ticket',
              onPressed: _close,
            ),
        ],
      ),
      body: ticket.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this ticket',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(ticketProvider(widget.ticketId)),
        ),
        data: (t) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.sm, Spacing.md, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(t.subject,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  StatusChip(t.status, dense: true),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                // Newest at the bottom, like every chat thread.
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: t.replies.length,
                itemBuilder: (context, index) =>
                    _ReplyBubble(reply: t.replies[index]),
              ),
            ),
            if (t.isClosed)
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Text(
                  'This ticket is closed — replying will reopen it.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            _buildComposer(context),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Spacing.md,
          right: Spacing.md,
          bottom: MediaQuery.of(context).viewInsets.bottom > 0
              ? Spacing.sm
              : Spacing.md,
          top: Spacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachments.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: Spacing.xs,
                  children: [
                    for (final (i, f) in _attachments.indexed)
                      InputChip(
                        label: Text(f.name,
                            style: theme.textTheme.labelSmall),
                        onDeleted: () =>
                            setState(() => _attachments.removeAt(i)),
                      ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'Attach files',
                  onPressed: _sending ? null : _pickAttachments,
                ),
                Expanded(
                  child: TextField(
                    controller: _message,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Write a reply…',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                IconButton.filled(
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyBubble extends ConsumerWidget {
  const _ReplyBubble({required this.reply});

  final TicketReply reply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mine = reply.isClient;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Spacing.sm),
        padding: const EdgeInsets.all(Spacing.md),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: mine
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: Radii.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                reply.authorName ?? (mine ? 'You' : 'Support'),
                if (reply.createdAt != null)
                  Formatting.dateTime(reply.createdAt),
              ].join(' · '),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.xs),
            Text(reply.message),
            for (final a in reply.attachments)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: ActionChip(
                  avatar: const Icon(Icons.attach_file, size: 16),
                  label: Text(a.originalName,
                      style: theme.textTheme.labelSmall),
                  onPressed: () => sharePdf(
                    context,
                    fetch: () =>
                        ref.read(portalServiceProvider).ticketAttachment(a.id),
                    filename: a.originalName,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

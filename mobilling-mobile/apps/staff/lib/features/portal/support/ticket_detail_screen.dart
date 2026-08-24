import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../common/share_pdf.dart';
import '../portal_providers.dart';

/// A ticket's reply thread, chat-style, with a composer pinned below.
///
/// Who said what is carried by alignment and by one tinted card against the
/// paper ones — a support thread is a conversation, not a status, so it gets
/// no colour of its own.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
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
      await ref
          .read(portalServiceProvider)
          .replyTicket(
            widget.ticketId,
            message: text,
            attachmentPaths: _attachments
                .map((f) => f.path!)
                .toList(growable: false),
          );
      _message.clear();
      _attachments.clear();
      ref.invalidate(portalTicketProvider(widget.ticketId));
      ref.invalidate(portalTicketsProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Close this ticket?',
          style: Type.display(22, color: theme.colorScheme.onSurface),
        ),
        content: const Text(
          'You can reopen it any time by sending another reply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it open'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close ticket'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(portalServiceProvider).closeTicket(widget.ticketId);
      ref.invalidate(portalTicketProvider(widget.ticketId));
      ref.invalidate(portalTicketsProvider);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ticket = ref.watch(portalTicketProvider(widget.ticketId));
    final open = ticket.valueOrNull != null && !ticket.value!.isClosed;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Support',
        title: ticket.valueOrNull?.ticketNumber ?? 'Ticket',
        trailing: open
            ? InkActionButton(
                icon: Icons.task_alt_outlined,
                tooltip: 'Close ticket',
                onPressed: _close,
              )
            : null,
      ),
      body: ticket.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this ticket',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(portalTicketProvider(widget.ticketId)),
        ),
        data: (t) => Column(
          children: [
            // The subject block: what the thread is about, once, above it.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.subject, style: theme.textTheme.titleMedium),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          [
                            t.department,
                            '${t.priority} priority',
                            if (t.createdAt != null)
                              'opened ${Formatting.date(t.createdAt)}',
                          ].join(' · ').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  StatusChip(t.status, dense: true),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: t.replies.isEmpty
                  ? const StateMessage(
                      icon: Icons.forum_outlined,
                      title: 'Nothing here yet',
                      message: 'Send a reply and support will pick it up.',
                    )
                  : ListView.builder(
                      // Newest at the bottom, like every chat thread.
                      padding: const EdgeInsets.all(Spacing.md),
                      itemCount: t.replies.length,
                      itemBuilder: (context, index) =>
                          _ReplyBubble(reply: t.replies[index]),
                    ),
            ),
            if (t.isClosed)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  0,
                  Spacing.md,
                  Spacing.sm,
                ),
                child: Text(
                  'This ticket is closed — replying will reopen it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            _Composer(
              controller: _message,
              attachments: _attachments,
              sending: _sending,
              onAttach: _pickAttachments,
              onRemoveAttachment: (i) =>
                  setState(() => _attachments.removeAt(i)),
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// The reply composer: a paper bar under a hairline, so it reads as chrome
/// rather than as another message.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.attachments,
    required this.sending,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final List<PlatformFile> attachments;
  final bool sending;
  final VoidCallback onAttach;
  final ValueChanged<int> onRemoveAttachment;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: Spacing.md,
            right: Spacing.md,
            bottom: MediaQuery.viewInsetsOf(context).bottom > 0
                ? Spacing.sm
                : Spacing.md,
            top: Spacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachments.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: Spacing.xs,
                    runSpacing: Spacing.xs,
                    children: [
                      for (final (i, f) in attachments.indexed)
                        InputChip(
                          label: Text(f.name),
                          onDeleted: () => onRemoveAttachment(i),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Attach files',
                    color: scheme.onSurfaceVariant,
                    onPressed: sending ? null : onAttach,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: !sending,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Write a reply…',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  IconButton.filled(
                    tooltip: 'Send reply',
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, size: 20),
                    onPressed: sending ? null : onSend,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One message in the thread. The client's own replies sit right on a lightly
/// tinted card; support's sit left on paper — the same hairline card the rest
/// of the app uses.
class _ReplyBubble extends ConsumerWidget {
  const _ReplyBubble({required this.reply});

  final TicketReply reply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mine = reply.isClient;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Spacing.sm),
        padding: const EdgeInsets.all(Spacing.md),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: mine
              ? scheme.primary.withValues(alpha: 0.06)
              : theme.cardTheme.color ?? scheme.surface,
          borderRadius: Radii.card,
          border: Border.all(
            color: mine
                ? scheme.primary.withValues(alpha: 0.22)
                : scheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                reply.authorName ?? (mine ? 'You' : 'Support'),
                if (reply.createdAt != null)
                  Formatting.dateTime(reply.createdAt),
              ].join(' · ').toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              reply.message,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            for (final a in reply.attachments)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: ActionChip(
                  avatar: const Icon(Icons.attach_file, size: 16),
                  label: Text(a.originalName),
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

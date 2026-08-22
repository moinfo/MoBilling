import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';

/// Staff view of a ticket thread, with reply and close/reopen.
/// Reply and status actions are permission-gated (tickets.reply /
/// tickets.manage) — the composer and menu hide when the role lacks them.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() =>
      _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await ref
          .read(staffServiceProvider)
          .replyTicket(widget.ticketId, message: text);
      _message.clear();
      ref.invalidate(ticketProvider(widget.ticketId));
      ref.invalidate(ticketsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await ref
          .read(staffServiceProvider)
          .setTicketStatus(widget.ticketId, status);
      ref.invalidate(ticketProvider(widget.ticketId));
      ref.invalidate(ticketsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(ticketProvider(widget.ticketId));
    final auth = ref.watch(sessionControllerProvider).session;
    final canReply = auth?.can(Permissions.ticketsReply) ?? false;
    final canManage = auth?.can('tickets.manage') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(ticket.valueOrNull?.ticketNumber ?? 'Ticket'),
        actions: [
          if (canManage && ticket.valueOrNull != null)
            PopupMenuButton<String>(
              onSelected: _setStatus,
              itemBuilder: (context) => [
                if (!ticket.value!.isClosed)
                  const PopupMenuItem(
                      value: 'closed', child: Text('Close ticket')),
                if (ticket.value!.isClosed)
                  const PopupMenuItem(
                      value: 'open', child: Text('Reopen ticket')),
                // No "Mark answered": `TicketController::updateStatus` only
                // accepts open|closed — `answered` is set automatically when
                // staff reply.
              ],
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.subject,
                            style: Theme.of(context).textTheme.titleSmall),
                        if (t.clientName != null)
                          Text(t.clientName!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                      ],
                    ),
                  ),
                  StatusChip(t.status, dense: true),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: t.replies.length,
                itemBuilder: (context, index) =>
                    _ReplyBubble(reply: t.replies[index]),
              ),
            ),
            if (canReply) _buildComposer(context),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _message,
                enabled: !_sending,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Reply to the client…',
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
      ),
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.reply});

  final TicketReply reply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Staff perspective: staff replies on the right, client's on the left.
    final mine = !reply.isClient;

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
                reply.authorName ?? (mine ? 'Staff' : 'Client'),
                if (reply.createdAt != null)
                  Formatting.dateTime(reply.createdAt),
              ].join(' · '),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.xs),
            Text(reply.message),
          ],
        ),
      ),
    );
  }
}

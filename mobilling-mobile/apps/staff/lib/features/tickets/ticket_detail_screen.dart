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

  /// A failed reply is a form error, so it sits above the composer rather
  /// than flashing past as a snackbar.
  String? _sendError;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref
          .read(staffServiceProvider)
          .replyTicket(widget.ticketId, message: text);
      _message.clear();
      ref.invalidate(ticketProvider(widget.ticketId));
      ref.invalidate(ticketsProvider);
    } on ApiException catch (e) {
      if (mounted) setState(() => _sendError = e.message);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// The status actions, as a sheet: one choice at a time, named for what
  /// it does. No "Mark answered" — `TicketController::updateStatus` only
  /// accepts open|closed, and `answered` is set automatically on reply.
  Future<void> _showActions(StaffTicket t) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.ticketNumber != null) ...[
                  Text(
                    t.ticketNumber!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                ],
                Text('Ticket actions', style: Type.display(22)),
                const SizedBox(height: Spacing.md),
                if (t.isClosed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_open_outlined),
                    title: const Text('Reopen ticket'),
                    subtitle: const Text('Puts it back in the open queue.'),
                    onTap: () => Navigator.pop(context, 'open'),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline),
                    title: const Text('Close ticket'),
                    subtitle: const Text(
                      'The client can still reply to reopen it.',
                    ),
                    onTap: () => Navigator.pop(context, 'closed'),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (choice != null) await _setStatus(choice);
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(ticketProvider(widget.ticketId));
    final auth = ref.watch(sessionControllerProvider).session;
    final canReply = auth?.can(Permissions.ticketsReply) ?? false;
    final canManage = auth?.can('tickets.manage') ?? false;
    final loaded = ticket.valueOrNull;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Support',
        title: loaded?.ticketNumber ?? 'Ticket',
        trailing: canManage && loaded != null
            ? InkActionButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Ticket actions',
                onPressed: () => _showActions(loaded),
              )
            : null,
      ),
      body: ticket.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this ticket',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(ticketProvider(widget.ticketId)),
        ),
        data: (t) => Column(
          children: [
            Reveal(child: _TicketHeader(ticket: t)),
            Expanded(
              child: t.replies.isEmpty
                  ? const StateMessage(
                      icon: Icons.forum_outlined,
                      title: 'No messages yet',
                      message: 'Reply below to start the thread.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.md,
                        Spacing.sm,
                        Spacing.md,
                        Spacing.md,
                      ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Material(
      color: theme.cardTheme.color ?? scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              keyboardUp ? Spacing.sm : Spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_sendError != null) ...[
                  ErrorBanner(message: _sendError!),
                  const SizedBox(height: Spacing.sm),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _message,
                        enabled: !_sending,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: _sendError == null
                            ? null
                            : (_) => setState(() => _sendError = null),
                        decoration: const InputDecoration(
                          hintText: 'Reply to the client…',
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    _SendButton(busy: _sending, onPressed: _send),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The subject as the screen's headline, with who it is from and how it
/// stands beneath — the figure a ticket is about is its state.
class _TicketHeader extends StatelessWidget {
  const _TicketHeader({required this.ticket});

  final StaffTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ticket.subject,
            style: Type.display(20, color: scheme.onSurface),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              StatusChip(ticket.status, dense: true),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  [
                    ticket.priority,
                    if (ticket.createdAt != null)
                      'opened ${Formatting.date(ticket.createdAt)}',
                  ].join(' · ').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (ticket.clientName != null || ticket.assigneeName != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              [
                if (ticket.clientName != null) ticket.clientName!,
                if (ticket.assigneeName != null)
                  'assigned to ${ticket.assigneeName}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The send action at the field's height, in the app's action blue.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 52,
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(52, 52),
        ),
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : const Icon(Icons.send_rounded, size: 20),
      ),
    );
  }
}

/// One message. Client messages sit left on a paper card; staff replies
/// sit right on the quiet container — two surfaces the theme already has,
/// so the thread needs no colour of its own.
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.reply});

  final TicketReply reply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Staff perspective: staff replies on the right, client's on the left.
    final mine = !reply.isClient;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            reply.authorName ?? (mine ? 'Staff' : 'Client'),
            if (reply.createdAt != null) Formatting.dateTime(reply.createdAt),
          ].join(' · ').toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(reply.message, style: theme.textTheme.bodyMedium),
      ],
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: mine
              ? Container(
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: Radii.card,
                  ),
                  child: body,
                )
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: body,
                  ),
                ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/attach_file.dart';
import '../common/share_pdf.dart';
import '../crm/crm_ui.dart' show CrmMetaLine, CrmSheet;
import 'tickets_tab.dart' show ticketStatsProvider;

/// The staff accounts a ticket can be assigned to.
///
/// `/users` sits behind `settings.users`, a heavier permission than the
/// `tickets.manage` that assigning itself needs, so this can fail with a 403
/// on a role that is genuinely allowed to route work — the picker says so
/// rather than looking broken.
final AutoDisposeFutureProvider<List<StaffUser>> assignableUsersProvider =
    FutureProvider.autoDispose<List<StaffUser>>(
      (ref) => ref.watch(staffServiceProvider).assignableUsers(),
    );

/// What the reply endpoint accepts: 5 files, 5 MB each.
const _maxAttachments = 5;
const _maxAttachmentBytes = 5 * 1024 * 1024;
const _attachmentExtensions = <String>[
  'pdf',
  'png',
  'jpg',
  'jpeg',
  'txt',
  'zip',
  'doc',
  'docx',
  'xls',
  'xlsx',
];

/// Staff view of a ticket thread, with reply, attachments, assignment and
/// close/reopen. Every action is gated on the permission its route requires
/// (tickets.reply / tickets.manage) — the composer and menu hide otherwise.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  final _message = TextEditingController();
  final List<Attachment> _attachments = [];
  bool _sending = false;

  /// Null until bytes start moving; 0–1 while they do. Only meaningful when
  /// there are files — a text reply is over before a bar could paint.
  double? _uploadProgress;

  /// A failed reply is a form error, so it sits above the composer rather
  /// than flashing past as a snackbar.
  String? _sendError;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  /// Add one file to the reply. Photos come off the camera, and PDFs get
  /// forwarded to support all the time, so the file browser stays available.
  Future<void> _attach() async {
    final picked = await pickAttachment(
      context,
      allowedExtensions: _attachmentExtensions,
    );
    if (picked == null || !mounted) return;

    // Refuse it here rather than after a slow upload ends in a 422.
    if (picked.bytes > _maxAttachmentBytes) {
      setState(
        () => _sendError =
            '${picked.name} is ${picked.readableSize} — the limit is 5 MB '
            'per file.',
      );
      return;
    }
    setState(() {
      _attachments.add(picked);
      _sendError = null;
    });
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;

    final files = _attachments.map((f) => f.path).toList(growable: false);
    setState(() {
      _sending = true;
      _sendError = null;
      _uploadProgress = files.isEmpty ? null : 0;
    });
    try {
      await ref
          .read(staffServiceProvider)
          .replyTicket(
            widget.ticketId,
            message: text,
            attachmentPaths: files,
            onProgress: files.isEmpty
                ? null
                : (sent, total) {
                    if (mounted && total > 0) {
                      setState(() => _uploadProgress = sent / total);
                    }
                  },
          );
      _message.clear();
      _attachments.clear();
      _invalidate();
    } on ApiException catch (e) {
      if (mounted) setState(() => _sendError = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await ref
          .read(staffServiceProvider)
          .setTicketStatus(widget.ticketId, status);
      _invalidate();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// Assign, reassign or unassign. The list is only fetchable with
  /// `settings.users`, so a 403 explains itself instead of showing nothing.
  Future<void> _assign(StaffTicket ticket) async {
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<({String? id, String name})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (context) => _AssignSheet(ticket: ticket),
    );
    if (choice == null) return;

    try {
      await ref
          .read(staffServiceProvider)
          .assignTicket(widget.ticketId, userId: choice.id);
      _invalidate();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            choice.id == null
                ? 'Ticket unassigned.'
                : 'Assigned to ${choice.name}.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Every mutation moves the queue counters too, so the rail on the tab
  /// behind this screen would otherwise go stale.
  void _invalidate() {
    ref.invalidate(ticketProvider(widget.ticketId));
    ref.invalidate(ticketsProvider);
    ref.invalidate(ticketStatsProvider);
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_search_outlined),
                  title: Text(
                    t.assigneeName == null
                        ? 'Assign ticket'
                        : 'Reassign ticket',
                  ),
                  subtitle: Text(
                    t.assigneeName == null
                        ? 'Nobody owns this yet.'
                        : 'Currently ${t.assigneeName}.',
                  ),
                  onTap: () => Navigator.pop(context, 'assign'),
                ),
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
    if (choice == null) return;
    if (choice == 'assign') {
      await _assign(t);
    } else {
      await _setStatus(choice);
    }
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
                // A receipt photo on a mobile connection is not instant, so
                // the wait is drawn rather than left to a frozen button.
                if (_uploadProgress != null) ...[
                  LinearProgressIndicator(value: _uploadProgress, minHeight: 2),
                  const SizedBox(height: Spacing.sm),
                ],
                if (_attachments.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: Spacing.xs,
                      runSpacing: Spacing.xs,
                      children: [
                        for (final (i, f) in _attachments.indexed)
                          InputChip(
                            label: Text(f.name),
                            isEnabled: !_sending,
                            onDeleted: _sending
                                ? null
                                : () =>
                                      setState(() => _attachments.removeAt(i)),
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
                      tooltip: 'Attach a photo or file',
                      color: scheme.onSurfaceVariant,
                      onPressed:
                          _sending || _attachments.length >= _maxAttachments
                          ? null
                          : _attach,
                    ),
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

/// Who owns this ticket. A list of the tenant's active staff, with the
/// current holder ticked and a way to hand it back to nobody.
class _AssignSheet extends ConsumerWidget {
  const _AssignSheet({required this.ticket});

  final StaffTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(assignableUsersProvider);
    final scheme = Theme.of(context).colorScheme;

    return CrmSheet(
      eyebrow: ticket.ticketNumber ?? 'Support',
      title: 'Assign ticket',
      children: [
        users.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Spacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => StateMessage(
            icon: Icons.lock_outline,
            title: 'Cannot list the team',
            // Reading /users needs settings.users, which routing tickets does
            // not imply — worth saying, because the role really can assign.
            message: error is ApiException
                ? error.message
                : 'Staff accounts are only readable with the settings.users '
                      'permission.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(assignableUsersProvider),
          ),
          data: (people) => Card(
            child: Column(
              children: [
                if (ticket.assigneeName != null) ...[
                  ListTile(
                    leading: Icon(
                      Icons.person_off_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                    title: const Text('Unassign'),
                    subtitle: const Text('Return it to the unowned queue.'),
                    onTap: () =>
                        Navigator.pop(context, (id: null, name: 'nobody')),
                  ),
                  const Divider(height: 1),
                ],
                for (final (i, person) in people.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(person.name),
                    subtitle: person.roleName == null
                        ? null
                        : CrmMetaLine(person.roleName!),
                    trailing: person.name == ticket.assigneeName
                        ? Icon(Icons.check_rounded, color: scheme.primary)
                        : null,
                    onTap: () => Navigator.pop(context, (
                      id: person.id,
                      name: person.name,
                    )),
                  ),
                ],
                if (people.isEmpty)
                  const ListTile(
                    title: Text('No active staff accounts'),
                    subtitle: Text('Add one under Settings › Team.'),
                  ),
              ],
            ),
          ),
        ),
      ],
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
class _ReplyBubble extends ConsumerWidget {
  const _ReplyBubble({required this.reply});

  final TicketReply reply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        // Ticket files live on the server's private disk, so each one is
        // streamed with the bearer token and handed to the share sheet —
        // the same route invoices and payslips already take.
        for (final attachment in reply.attachments)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: ActionChip(
              avatar: const Icon(Icons.attach_file, size: 16),
              label: Text(attachment.originalName),
              tooltip: attachment.size == null
                  ? 'Download'
                  : 'Download · ${(attachment.size! / 1024).round()} KB',
              onPressed: () => sharePdf(
                context,
                fetch: () => ref
                    .read(staffServiceProvider)
                    .ticketAttachment(attachment.id),
                filename: attachment.originalName,
              ),
            ),
          ),
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

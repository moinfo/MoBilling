import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView;
import 'support_admin_providers.dart';

/// Canned replies: the saved answers staff paste into tickets.
class CannedRepliesScreen extends ConsumerWidget {
  const CannedRepliesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replies = ref.watch(cannedRepliesProvider);
    final canManage =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(SupportAdminPermissions.ticketsManage) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Support',
        title: 'Canned replies',
        trailing: !canManage
            ? null
            : InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'New canned reply',
                onPressed: () => _edit(context, ref, null),
              ),
      ),
      body: CrmAsyncView(
        value: replies,
        errorTitle: 'Could not load canned replies',
        onRetry: () => ref.invalidate(cannedRepliesProvider),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.quickreply_outlined,
                title: 'No canned replies',
                message: 'Saved answers you can paste into tickets go here.',
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(cannedRepliesProvider.future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xl,
                  ),
                  children: [
                    const SectionHeader('Saved answers'),
                    const SizedBox(height: Spacing.sm),
                    // One card, rows divided by hairlines — the list shape
                    // the rest of the app uses.
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (i, reply) in items.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _ReplyRow(reply: reply, canManage: canManage),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// One reply: the title, and a mono line saying when it was last touched —
/// the fact that decides whether an answer is still the right answer.
class _ReplyRow extends ConsumerWidget {
  const _ReplyRow({required this.reply, required this.canManage});

  final CannedReply reply;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: () => _openActions(context, ref, reply, canManage),
      title: Text(
        reply.title,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: reply.updatedAt == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'updated ${Formatting.date(reply.updatedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

/// The reply in full, with the actions under it. Copying is the thing this
/// screen exists for, so it leads.
Future<void> _openActions(
  BuildContext context,
  WidgetRef ref,
  CannedReply reply,
  bool canManage,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    Spacing.lg,
                    Spacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CANNED REPLY',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        reply.title,
                        style: Type.display(22, color: scheme.onSurface),
                      ),
                      const SizedBox(height: Spacing.md),
                      Text(reply.body, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy reply text'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (canManage) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit reply'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  'Delete reply',
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;

  try {
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: reply.body));
        messenger.showSnackBar(const SnackBar(content: Text('Copied.')));
        return;
      case 'edit':
        final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
          builder: (_) => _CannedReplyForm(existing: reply),
        );
        if (!(saved ?? false)) return;
      case 'delete':
        final sure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete “${reply.title}”?'),
            content: const Text(
              'Staff will no longer be able to insert it into a ticket.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (!(sure ?? false)) return;
        await ref.read(supportAdminServiceProvider).deleteCannedReply(reply.id);
        messenger.showSnackBar(const SnackBar(content: Text('Reply deleted.')));
    }
    ref.invalidate(cannedRepliesProvider);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> _edit(
  BuildContext context,
  WidgetRef ref,
  CannedReply? existing,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (_) => _CannedReplyForm(existing: existing),
  );
  if (saved ?? false) ref.invalidate(cannedRepliesProvider);
}

class _CannedReplyForm extends ConsumerStatefulWidget {
  const _CannedReplyForm({this.existing});

  final CannedReply? existing;

  @override
  ConsumerState<_CannedReplyForm> createState() => _CannedReplyFormState();
}

class _CannedReplyFormState extends ConsumerState<_CannedReplyForm> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _body = TextEditingController(text: widget.existing?.body ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'Both a title and a body are required.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(supportAdminServiceProvider);
      final existing = widget.existing;
      if (existing == null) {
        await service.createCannedReply(
          title: _title.text.trim(),
          body: _body.text.trim(),
        );
      } else {
        await service.updateCannedReply(
          existing.id,
          title: _title.text.trim(),
          body: _body.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('title') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'CANNED REPLIES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              widget.existing == null ? 'New canned reply' : 'Edit reply',
              style: Type.display(22, color: scheme.onSurface),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            const FieldLabel('Title'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _title,
              enabled: !_submitting,
              decoration: const InputDecoration(
                hintText: 'How staff will find it',
              ),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Reply text'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _body,
              enabled: !_submitting,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                hintText: 'The answer, exactly as it should be pasted',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting ? 'Saving…' : 'Save reply',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable picker so the ticket composer can insert a canned reply.
/// Returns the chosen body text, or null if dismissed.
class CannedReplyPickerSheet extends ConsumerWidget {
  const CannedReplyPickerSheet({super.key});

  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        builder: (_) => const CannedReplyPickerSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replies = ref.watch(cannedRepliesProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CANNED REPLIES',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Insert a reply',
                  style: Type.display(22, color: scheme.onSurface),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: replies.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Spacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: ErrorBanner(
                  message: error is ApiException
                      ? error.message
                      : 'Could not load replies.',
                ),
              ),
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: Spacing.xl),
                      child: StateMessage(
                        icon: Icons.quickreply_outlined,
                        title: 'No canned replies',
                        message: 'Saved answers appear here once created.',
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final reply = items[index];
                        return ListTile(
                          title: Text(
                            reply.title,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            reply.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(reply.body),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}


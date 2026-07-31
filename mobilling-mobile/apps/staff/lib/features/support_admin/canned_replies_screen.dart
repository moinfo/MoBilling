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
    final canManage = ref.watch(sessionControllerProvider).session?.can(
              SupportAdminPermissions.ticketsManage,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Canned replies')),
      floatingActionButton: !canManage
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('New reply'),
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
            : ListView.separated(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final reply = items[index];
                  return Card(
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(reply.title),
                      childrenPadding: const EdgeInsets.fromLTRB(
                          Spacing.md, 0, Spacing.md, Spacing.sm),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reply.body,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: Spacing.sm),
                        Row(
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.copy_outlined, size: 16),
                              label: const Text('Copy'),
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: reply.body));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Copied.')));
                                }
                              },
                            ),
                            if (canManage) ...[
                              TextButton(
                                onPressed: () => _edit(context, ref, reply),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: () => _delete(context, ref, reply),
                                child: Text('Delete',
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, CannedReply reply) async {
    // Captured before the dialog await — the context may be gone afterwards.
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${reply.title}”?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true) return;

    try {
      await ref.read(supportAdminServiceProvider).deleteCannedReply(reply.id);
      ref.invalidate(cannedRepliesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, CannedReply? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _CannedReplyForm(existing: existing),
    );
    if (saved == true) ref.invalidate(cannedRepliesProvider);
  }
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
            title: _title.text.trim(), body: _body.text.trim());
      } else {
        await service.updateCannedReply(existing.id,
            title: _title.text.trim(), body: _body.text.trim());
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
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'New canned reply' : 'Edit reply',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.sm),
            ],
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _body,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reply text',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Saving…' : 'Save'),
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
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        builder: (_) => const CannedReplyPickerSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replies = ref.watch(cannedRepliesProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Text('Insert a canned reply',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Flexible(
            child: replies.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Spacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Text(error is ApiException
                    ? error.message
                    : 'Could not load replies.'),
              ),
              data: (items) => ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final reply = items[index];
                  return ListTile(
                    title: Text(reply.title),
                    subtitle: Text(reply.body,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart' show CrmAsyncView;
import 'support_admin_providers.dart';

/// Announcements shown to every client in their portal.
///
/// Staff see drafts as well as published items; publishing is a field on the
/// update call rather than a separate endpoint, so the switch in the editor is
/// the publish action.
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(staffAnnouncementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: CrmAsyncView(
        value: announcements,
        errorTitle: 'Could not load announcements',
        onRetry: () => ref.invalidate(staffAnnouncementsProvider),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.campaign_outlined,
                title: 'No announcements yet',
                message: 'Published announcements appear in every client portal.',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(item.title,
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                              ),
                              StatusChip(item.status, dense: true),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.isPublished && item.publishedAt != null
                                ? 'Published ${Formatting.date(item.publishedAt)}'
                                : 'Draft · created ${Formatting.date(item.createdAt)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            htmlToPlainText(item.body),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: Spacing.xs),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _edit(context, ref, item),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _togglePublish(context, ref, item),
                                child: Text(item.isPublished
                                    ? 'Unpublish'
                                    : 'Publish'),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(context, ref, item),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _togglePublish(
      BuildContext context, WidgetRef ref, StaffAnnouncement item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supportAdminServiceProvider).updateAnnouncement(
            item.id,
            title: item.title,
            body: item.body,
            isPublished: !item.isPublished,
          );
      ref.invalidate(staffAnnouncementsProvider);
      messenger.showSnackBar(SnackBar(
          content:
              Text(item.isPublished ? 'Unpublished.' : 'Published to clients.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, StaffAnnouncement item) async {
    // Captured before the dialog await — the context may be gone afterwards.
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${item.title}”?'),
        content: const Text('Clients will no longer see it.'),
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
      await ref.read(supportAdminServiceProvider).deleteAnnouncement(item.id);
      ref.invalidate(staffAnnouncementsProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref,
      StaffAnnouncement? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _AnnouncementForm(existing: existing),
    );
    if (saved == true) ref.invalidate(staffAnnouncementsProvider);
  }
}

class _AnnouncementForm extends ConsumerStatefulWidget {
  const _AnnouncementForm({this.existing});

  final StaffAnnouncement? existing;

  @override
  ConsumerState<_AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends ConsumerState<_AnnouncementForm> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _published;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    // Existing bodies are HTML from the web editor; editing them on mobile as
    // plain text would silently strip markup, so the raw HTML is shown.
    _body = TextEditingController(text: widget.existing?.body ?? '');
    _published = widget.existing?.isPublished ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'A title and body are required.');
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
        await service.createAnnouncement(
          title: _title.text.trim(),
          body: _body.text.trim(),
          isPublished: _published,
        );
      } else {
        await service.updateAnnouncement(
          existing.id,
          title: _title.text.trim(),
          body: _body.text.trim(),
          isPublished: _published,
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
    final isHtml = _body.text.contains('<');

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
            Text(
                widget.existing == null
                    ? 'New announcement'
                    : 'Edit announcement',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.sm),
            ],
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _body,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Body',
                alignLabelWithHint: true,
                // Honest about the trade-off rather than quietly mangling it.
                helperText: isHtml
                    ? 'Contains HTML from the web editor — edit carefully'
                    : 'Plain text',
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Published'),
              subtitle: const Text('Visible in every client portal'),
              value: _published,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _published = v),
            ),
            const SizedBox(height: Spacing.md),
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

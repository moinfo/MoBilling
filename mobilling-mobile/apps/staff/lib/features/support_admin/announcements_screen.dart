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
///
/// Drafts lead, because a draft is the row that still needs someone — a
/// published announcement is finished work.
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(staffAnnouncementsProvider);
    final status = context.statusColors;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Communications',
        title: 'Announcements',
        trailing: InkActionButton(
          icon: Icons.add_rounded,
          tooltip: 'New announcement',
          onPressed: () => _edit(context, ref, null),
        ),
      ),
      body: CrmAsyncView(
        value: announcements,
        errorTitle: 'Could not load announcements',
        onRetry: () => ref.invalidate(staffAnnouncementsProvider),
        builder: (items) {
          if (items.isEmpty) {
            return const StateMessage(
              icon: Icons.campaign_outlined,
              title: 'No announcements yet',
              message: 'Published announcements appear in every client portal.',
            );
          }

          final drafts = [
            for (final i in items)
              if (!i.isPublished) i,
          ];
          final published = [
            for (final i in items)
              if (i.isPublished) i,
          ];

          return RefreshIndicator(
            onRefresh: () => ref.refresh(staffAnnouncementsProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xl,
              ),
              children: [
                StatRail(
                  items: [
                    StatRailItem(
                      label: 'Published',
                      value: Formatting.integer(published.length),
                    ),
                    StatRailItem(
                      label: 'Drafts',
                      value: Formatting.integer(drafts.length),
                      emphasis: drafts.isEmpty ? null : status.attention,
                    ),
                  ],
                ),
                if (drafts.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  const SectionHeader('Drafts'),
                  const SizedBox(height: Spacing.sm),
                  _AnnouncementCard(items: drafts),
                ],
                if (published.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  const SectionHeader('Live in the portal'),
                  const SizedBox(height: Spacing.sm),
                  _AnnouncementCard(items: published),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    StaffAnnouncement? existing,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _AnnouncementForm(existing: existing),
    );
    if (saved ?? false) ref.invalidate(staffAnnouncementsProvider);
  }
}

/// One card, rows divided by hairlines — the list shape used everywhere else
/// in the app, so a list of announcements reads as the same instrument as a
/// list of domains.
class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.items});

  final List<StaffAnnouncement> items;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _AnnouncementRow(item: item),
        ],
      ],
    ),
  );
}

/// One announcement: the title, then the state chip beside a mono line saying
/// when it went out (or when the draft was started).
class _AnnouncementRow extends ConsumerWidget {
  const _AnnouncementRow({required this.item});

  final StaffAnnouncement item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: () => _openActions(context, ref, item),
      title: Text(
        item.title,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            StatusChip(item.status, dense: true),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                item.isPublished && item.publishedAt != null
                    ? 'published ${Formatting.date(item.publishedAt)}'
                    : 'created ${Formatting.date(item.createdAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

/// The row's actions, with the body shown as read so nobody has to open the
/// editor just to remember what an announcement said.
Future<void> _openActions(
  BuildContext context,
  WidgetRef ref,
  StaffAnnouncement item,
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
      final meta = theme.textTheme.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
      );

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
                        item.title,
                        style: Type.display(22, color: scheme.onSurface),
                      ),
                      const SizedBox(height: Spacing.sm),
                      Row(
                        children: [
                          StatusChip(item.status, dense: true),
                          const SizedBox(width: Spacing.sm),
                          Flexible(
                            child: Text(
                              item.isPublished && item.publishedAt != null
                                  ? 'published ${Formatting.date(item.publishedAt)}'
                                  : 'created ${Formatting.date(item.createdAt)}',
                              style: meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.md),
                      Text(
                        htmlToPlainText(item.body),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit announcement'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                item.isPublished
                    ? Icons.visibility_off_outlined
                    : Icons.campaign_outlined,
              ),
              title: Text(
                item.isPublished ? 'Unpublish' : 'Publish to clients',
              ),
              onTap: () => Navigator.pop(context, 'publish'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(
                'Delete announcement',
                style: TextStyle(color: scheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;

  final service = ref.read(supportAdminServiceProvider);
  try {
    switch (action) {
      case 'edit':
        final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
          builder: (_) => _AnnouncementForm(existing: item),
        );
        if (!(saved ?? false)) return;
      case 'publish':
        await service.updateAnnouncement(
          item.id,
          title: item.title,
          body: item.body,
          isPublished: !item.isPublished,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              item.isPublished ? 'Unpublished.' : 'Published to clients.',
            ),
          ),
        );
      case 'delete':
        if (!await _confirmDelete(context, item.title)) return;
        await service.deleteAnnouncement(item.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Announcement deleted.')),
        );
    }
    ref.invalidate(staffAnnouncementsProvider);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<bool> _confirmDelete(BuildContext context, String title) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete “$title”?'),
      content: const Text('Clients will no longer see it.'),
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
  return sure ?? false;
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isHtml = _body.text.contains('<');

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
              'ANNOUNCEMENTS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              widget.existing == null
                  ? 'New announcement'
                  : 'Edit announcement',
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
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What clients will see first',
              ),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Body'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _body,
              enabled: !_submitting,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                alignLabelWithHint: true,
                hintText: 'The announcement itself',
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
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting ? 'Saving…' : 'Save announcement',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}


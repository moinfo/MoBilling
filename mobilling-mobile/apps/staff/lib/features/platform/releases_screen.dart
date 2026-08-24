import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../crm/crm_ui.dart'
    show
        CrmCardList,
        CrmDetailRow,
        CrmField,
        CrmPickerField,
        CrmSheet,
        CrmStatusLine,
        showCrmMessage,
        showCrmSheet;
import 'platform_providers.dart' show platformServiceProvider;
import 'platform_shell.dart' show PlatformListScaffold;

/// The "Check for Updates" catalog self-hosted installs compare their
/// version against — the newest active row is the latest.
final AutoDisposeFutureProvider<List<Release>> releasesProvider =
    FutureProvider.autoDispose<List<Release>>(
      (ref) => ref.watch(platformServiceProvider).releases(),
    );

class ReleasesScreen extends ConsumerWidget {
  const ReleasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformListScaffold<Release>(
      title: 'Releases',
      value: ref.watch(releasesProvider),
      onRetry: () => ref.invalidate(releasesProvider),
      emptyIcon: Icons.rocket_launch_outlined,
      emptyTitle: 'No releases published yet',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'publish-release',
        onPressed: () => _publish(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Publish release'),
      ),
      itemBuilder: (context, release) => _ReleaseRow(release: release),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _ReleaseFormSheet(),
    );
    if (saved == true) ref.invalidate(releasesProvider);
  }
}

class _ReleaseRow extends ConsumerWidget {
  const _ReleaseRow({required this.release});

  final Release release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      title: Text(release.version, style: theme.textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: CrmStatusLine(
          status: release.isActive ? 'active' : 'draft',
          meta: 'released ${Formatting.date(release.releasedAt)}',
        ),
      ),
      trailing: Icon(Icons.chevron_right, size: 20, color: scheme.outline),
      onTap: () => _open(context, ref),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final choice = await showCrmSheet<String>(
      context: context,
      builder: (_) => _ReleaseDetailSheet(release: release),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'open':
        await launchUrl(
          Uri.parse(release.downloadUrl!),
          mode: LaunchMode.externalApplication,
        );
      case 'edit':
        final saved = await showCrmSheet<bool>(
          context: context,
          builder: (_) => _ReleaseFormSheet(existing: release),
        );
        if (saved == true) ref.invalidate(releasesProvider);
      case 'delete':
        await _delete(context, ref);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete release ${release.version}?',
          style: Type.display(22, color: scheme.onSurface),
        ),
        content: const Text(
          'Self-hosted installs will no longer see this version when '
          'checking for updates. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final message = await ref
          .read(platformServiceProvider)
          .deleteRelease(release.id);
      ref.invalidate(releasesProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Release deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _ReleaseDetailSheet extends StatelessWidget {
  const _ReleaseDetailSheet({required this.release});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CrmSheet(
      eyebrow: release.isActive ? 'Active' : 'Draft',
      title: release.version,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CrmDetailRow('Released', Formatting.date(release.releasedAt)),
                if (release.downloadUrl != null)
                  CrmDetailRow('Download', release.downloadUrl!),
                if (release.changelog != null && release.changelog!.isNotEmpty)
                  CrmDetailRow('Changelog', release.changelog!),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        CrmCardList(
          children: [
            if (release.downloadUrl != null)
              ListTile(
                leading: const Icon(Icons.open_in_new, size: 20),
                title: const Text('Open download URL'),
                onTap: () => Navigator.pop(context, 'open'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                size: 20,
                color: scheme.error,
              ),
              title: Text(
                'Delete release',
                style: TextStyle(color: scheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReleaseFormSheet extends ConsumerStatefulWidget {
  const _ReleaseFormSheet({this.existing});

  final Release? existing;

  @override
  ConsumerState<_ReleaseFormSheet> createState() => _ReleaseFormSheetState();
}

class _ReleaseFormSheetState extends ConsumerState<_ReleaseFormSheet> {
  final _version = TextEditingController();
  final _changelog = TextEditingController();
  final _downloadUrl = TextEditingController();
  late DateTime _releasedAt;
  late bool _isActive;

  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _version.text = existing?.version ?? '';
    _changelog.text = existing?.changelog ?? '';
    _downloadUrl.text = existing?.downloadUrl ?? '';
    _releasedAt = existing?.releasedAt ?? DateTime.now();
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _version.dispose();
    _changelog.dispose();
    _downloadUrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _releasedAt,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _releasedAt = picked);
  }

  Future<void> _submit() async {
    if (_version.text.trim().isEmpty) {
      setState(() => _error = 'Enter a version.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final version = _version.text.trim();
    final changelog = _changelog.text.trim().isEmpty
        ? null
        : _changelog.text.trim();
    final downloadUrl = _downloadUrl.text.trim().isEmpty
        ? null
        : _downloadUrl.text.trim();

    try {
      final service = ref.read(platformServiceProvider);
      if (_isEdit) {
        await service.updateRelease(
          widget.existing!.id,
          version: version,
          changelog: changelog,
          downloadUrl: downloadUrl,
          releasedAt: _releasedAt,
          isActive: _isActive,
        );
      } else {
        await service.createRelease(
          version: version,
          changelog: changelog,
          downloadUrl: downloadUrl,
          releasedAt: _releasedAt,
          isActive: _isActive,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(
        context,
        _isEdit ? 'Release updated.' : 'Release published.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CrmSheet(
      title: _isEdit ? 'Edit release' : 'Publish release',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Version',
          child: TextField(
            controller: _version,
            enabled: !_submitting,
            decoration: const InputDecoration(hintText: '2.1.0'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Released',
          value: Formatting.date(_releasedAt),
          onTap: _submitting ? null : _pickDate,
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Changelog',
          child: TextField(
            controller: _changelog,
            enabled: !_submitting,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '- Fixed X\n- Added Y'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Download URL',
          child: TextField(
            controller: _downloadUrl,
            enabled: !_submitting,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://…/mobilling-2.1.0.zip',
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Active', style: Theme.of(context).textTheme.titleSmall),
          subtitle: const Text('Shown as latest to self-hosted installs'),
          value: _isActive,
          onChanged: _submitting ? null : (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : (_isEdit ? 'Save' : 'Publish'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

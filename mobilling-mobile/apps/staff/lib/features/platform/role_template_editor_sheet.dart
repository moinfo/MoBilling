import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart' show CrmMetaLine;
import 'platform_providers.dart';

/// Edit one role template's permission set — `RoleTemplateController::update`.
///
/// Same checklist shape as the tenant-role editor
/// (`apps/staff/lib/features/admin/role_editor_sheet.dart`), fit to a
/// template: there is no name or slug to edit, and saving asks for
/// confirmation first, because this one write rewrites every existing
/// tenant's system role of this type at once — the same "Changes apply to
/// all tenants" warning the web's `Roles.tsx` carries.
Future<void> showRoleTemplateEditor(
  BuildContext context,
  RoleTemplate template,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
  builder: (_) => _RoleTemplateEditorSheet(template: template),
);

class _RoleTemplateEditorSheet extends ConsumerStatefulWidget {
  const _RoleTemplateEditorSheet({required this.template});

  final RoleTemplate template;

  @override
  ConsumerState<_RoleTemplateEditorSheet> createState() =>
      _RoleTemplateEditorSheetState();
}

class _RoleTemplateEditorSheetState
    extends ConsumerState<_RoleTemplateEditorSheet> {
  final _search = TextEditingController();

  /// Null until the detail load seeds it once. A set, because the API syncs
  /// the whole list and order carries no meaning.
  Set<String>? _selected;

  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detailProvider = roleTemplateDetailProvider(widget.template.type);
    final detailAsync = ref.watch(detailProvider);
    final insets = sheetBottomInset(context);
    final height = math.max(
      280.0,
      MediaQuery.sizeOf(context).height * 0.92 - insets,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: height,
        child: detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => StateMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load permissions',
            message: error is ApiException ? error.message : null,
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(detailProvider),
          ),
          data: (detail) {
            _selected ??= {...detail.enabledIds};
            final catalogue = detail.catalogue;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _identity(theme)),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _TemplatePermissionsBar(
                          background: scheme.surface,
                          selected: _selected!.length,
                          total: catalogue.total,
                          controller: _search,
                          query: _search.text,
                        ),
                      ),
                      ..._groupSlivers(catalogue, theme),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: Spacing.lg),
                      ),
                    ],
                  ),
                ),
                _footer(theme),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _identity(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ROLE TEMPLATE',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          widget.template.label,
          style: Type.display(22, color: theme.colorScheme.onSurface),
        ),
        if (widget.template.tenantsCount != null) ...[
          const SizedBox(height: Spacing.sm),
          CrmMetaLine(
            'Applies to ${Formatting.integer(widget.template.tenantsCount!)} '
            'tenant${widget.template.tenantsCount == 1 ? '' : 's'} right now, '
            'and every new one seeded with this type',
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: Spacing.md),
          ErrorBanner(message: _error!),
        ],
      ],
    ),
  );

  List<Widget> _groupSlivers(PermissionCatalogue data, ThemeData theme) {
    final query = _search.text.trim().toLowerCase();
    final scheme = theme.colorScheme;

    final slivers = <Widget>[];
    String? lastCategory;
    var anyShown = false;

    for (final group in data.groups) {
      final matches = query.isEmpty
          ? group.permissions
          : group.permissions
                .where(
                  (p) =>
                      p.name.toLowerCase().contains(query) ||
                      p.displayLabel.toLowerCase().contains(query),
                )
                .toList(growable: false);
      if (matches.isEmpty) continue;
      anyShown = true;

      if (group.category != lastCategory) {
        lastCategory = group.category;
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                Spacing.sm,
              ),
              child: SectionHeader(
                PermissionCatalogue.categoryLabel(group.category),
              ),
            ),
          ),
        );
      }

      final ids = matches.map((p) => p.id).toList(growable: false);
      final onCount = ids.where(_selected!.contains).length;

      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.sm,
            ),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    dense: true,
                    tristate: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: onCount == 0
                        ? false
                        : onCount == ids.length
                        ? true
                        : null,
                    title: Text(group.name, style: theme.textTheme.titleSmall),
                    secondary: Text(
                      '$onCount/${ids.length}',
                      style: Type.mono(11, color: scheme.onSurfaceVariant),
                    ),
                    onChanged: _busy
                        ? null
                        : (_) => setState(() {
                            if (onCount == ids.length) {
                              _selected!.removeAll(ids);
                            } else {
                              _selected!.addAll(ids);
                            }
                          }),
                  ),
                  const Divider(height: 1),
                  for (final permission in matches)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected!.contains(permission.id),
                      title: Text(
                        permission.displayLabel,
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: CrmMetaLine(permission.name),
                      ),
                      onChanged: _busy
                          ? null
                          : (on) => setState(() {
                              if (on ?? false) {
                                _selected!.add(permission.id);
                              } else {
                                _selected!.remove(permission.id);
                              }
                            }),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!anyShown) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Text(
              data.isEmpty
                  ? 'No permissions in this catalogue.'
                  : 'Nothing matches “${_search.text.trim()}”.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  Widget _footer(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: PrimaryButton(
        label: 'Save template',
        busy: _busy,
        onPressed: _busy ? null : _confirmAndSave,
      ),
    );
  }

  /// Confirms first — this write applies to every tenant of this role type
  /// at once, not just a preview — then saves.
  Future<void> _confirmAndSave() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Update the ${widget.template.label} template?'),
        content: Text(
          'Changes apply to all tenants: every existing tenant whose role '
          'is still the default ${widget.template.label} template will have '
          'its permissions synced to match, and every new tenant will start '
          'from this set. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _save();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final message = await ref
          .read(platformServiceProvider)
          .updateRoleTemplate(
            widget.template.type,
            _selected!.toList(growable: false),
          );
      ref.invalidate(roleTemplatesProvider);
      ref.invalidate(roleTemplateDetailProvider(widget.template.type));
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            message ?? '${widget.template.label} template updated.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }
}

/// The pinned strip: the running count and the search box. Same shape as the
/// tenant-role editor's, kept file-local since neither is shared.
class _TemplatePermissionsBar extends SliverPersistentHeaderDelegate {
  const _TemplatePermissionsBar({
    required this.background,
    required this.selected,
    required this.total,
    required this.controller,
    required this.query,
  });

  final Color background;
  final int selected;
  final int total;
  final TextEditingController controller;
  final String query;

  static const _height = 112.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.xs,
          Spacing.lg,
          Spacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'PERMISSIONS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${Formatting.integer(selected)} / '
                  '${Formatting.integer(total)}',
                  style: Type.mono(
                    12,
                    color: selected == 0 ? scheme.error : scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              height: 44,
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search permissions',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: controller.clear,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_TemplatePermissionsBar old) =>
      old.selected != selected ||
      old.total != total ||
      old.query != query ||
      old.background != background ||
      old.controller != controller;
}

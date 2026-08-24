import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart' show CrmField, CrmMetaLine;
import 'admin_providers.dart';

/// Create or edit a role.
///
/// Returns true when something was written and the caller should reload.
///
/// The web puts the whole permission catalogue in a wide grid of category
/// cards (`mobilling-ui/src/pages/Roles.tsx`). A phone cannot hold that grid,
/// so the same catalogue becomes one searchable checklist in a full-height
/// sheet: the search box and the running count stay pinned while the groups
/// scroll under them, because "how many did I just grant" is the question a
/// permission editor has to answer at every moment.
Future<bool?> showRoleEditor(BuildContext context, {StaffRole? role}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // Set explicitly so the pinned header can paint the identical colour
      // and disappear into the sheet as it scrolls under it.
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _RoleEditorSheet(role: role),
    );

class _RoleEditorSheet extends ConsumerStatefulWidget {
  const _RoleEditorSheet({required this.role});

  final StaffRole? role;

  @override
  ConsumerState<_RoleEditorSheet> createState() => _RoleEditorSheetState();
}

class _RoleEditorSheetState extends ConsumerState<_RoleEditorSheet> {
  late final TextEditingController _slug;
  late final TextEditingController _label;
  final _search = TextEditingController();

  /// The permission UUIDs currently ticked. A set, because the API syncs the
  /// whole list and order carries no meaning.
  late final Set<String> _selected;

  String? _error;
  bool _busy = false;

  bool get _isNew => widget.role == null;

  @override
  void initState() {
    super.initState();
    final role = widget.role;
    _slug = TextEditingController(text: role?.name ?? '');
    _label = TextEditingController(text: role?.label ?? role?.name ?? '');
    _selected = {...?role?.permissionIds};
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _slug.dispose();
    _label.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final catalogue = ref.watch(availablePermissionsProvider);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final height = math.max(
      280.0,
      MediaQuery.sizeOf(context).height * 0.92 - insets,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: height,
        child: catalogue.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => StateMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load permissions',
            message: error is ApiException ? error.message : null,
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(availablePermissionsProvider),
          ),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _identity(theme)),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PermissionsBar(
                        background: scheme.surface,
                        selected: _selected.length,
                        total: data.total,
                        controller: _search,
                        query: _search.text,
                      ),
                    ),
                    ..._groupSlivers(data, theme),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: Spacing.lg),
                    ),
                  ],
                ),
              ),
              _footer(theme),
            ],
          ),
        ),
      ),
    );
  }

  /// Who the role is: the human name, and on creation the immutable slug.
  Widget _identity(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ROLE',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          _isNew ? 'New role' : widget.role!.displayName,
          style: Type.display(22, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: Spacing.lg),
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Display name',
          child: TextField(
            controller: _label,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Accountant'),
          ),
        ),
        if (_isNew) ...[
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Slug',
            child: TextField(
              controller: _slug,
              autocorrect: false,
              inputFormatters: [
                // The API validates `^[a-z0-9_]+$`; refusing the other keys
                // outright beats explaining the rule after a round trip.
                FilteringTextInputFormatter.allow(RegExp('[a-z0-9_]')),
              ],
              decoration: const InputDecoration(
                hintText: 'accountant',
                helperText: 'Lowercase, no spaces. Cannot be changed later.',
              ),
            ),
          ),
        ] else if (widget.role!.isSystem) ...[
          const SizedBox(height: Spacing.sm),
          CrmMetaLine('System role · ${widget.role!.name}'),
        ] else ...[
          const SizedBox(height: Spacing.sm),
          CrmMetaLine(widget.role!.name),
        ],
      ],
    ),
  );

  /// One card per `group_name`, with a category eyebrow whenever the category
  /// changes — the grouping the web uses, flattened into a single column.
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
      final onCount = ids.where(_selected.contains).length;

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
                  // Whole-group toggle. Indeterminate when partly on, so the
                  // control states what it would do rather than guessing.
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
                    onChanged: (_) => setState(() {
                      if (onCount == ids.length) {
                        _selected.removeAll(ids);
                      } else {
                        _selected.addAll(ids);
                      }
                    }),
                  ),
                  const Divider(height: 1),
                  for (final permission in matches)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(permission.id),
                      title: Text(
                        permission.displayLabel,
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: CrmMetaLine(permission.name),
                      ),
                      onChanged: (on) => setState(() {
                        if (on ?? false) {
                          _selected.add(permission.id);
                        } else {
                          _selected.remove(permission.id);
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
                  ? 'No permissions are available to this organisation.'
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
    // System roles are refused by the API, and so is a role with users on it
    // — the button is only offered where it can actually work.
    final canDelete = !_isNew && !widget.role!.isSystem;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            label: _isNew ? 'Create role' : 'Save role',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
          if (canDelete) ...[
            const SizedBox(height: Spacing.xs),
            TextButton.icon(
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: _busy ? null : scheme.error,
              ),
              label: Text(
                'Delete role',
                style: TextStyle(color: _busy ? null : scheme.error),
              ),
              onPressed: _busy ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final slug = _slug.text.trim();

    String? complaint;
    if (label.isEmpty) {
      complaint = 'Give the role a display name.';
    } else if (_isNew && slug.isEmpty) {
      complaint =
          'Give the role a slug — lowercase letters, numbers and '
          'underscores.';
    } else if (_selected.isEmpty) {
      complaint = 'A role must grant at least one permission.';
    }
    if (complaint != null) {
      setState(() => _error = complaint);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final permissionIds = _selected.toList(growable: false);
    try {
      final service = ref.read(adminServiceProvider);
      if (_isNew) {
        await service.createRole(
          name: slug,
          label: label,
          permissionIds: permissionIds,
        );
      } else {
        await service.updateRole(
          widget.role!.id,
          label: label,
          permissionIds: permissionIds,
        );
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_isNew ? '$label created.' : '$label saved.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _delete() async {
    final role = widget.role!;
    final scheme = Theme.of(context).colorScheme;

    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete the ${role.displayName} role?'),
        content: Text(
          role.usersCount > 0
              ? '${Formatting.integer(role.usersCount)} '
                    '${role.usersCount == 1 ? 'person is' : 'people are'} on '
                    'this role. Move them to another role first — the server '
                    'will refuse until you do.'
              : 'The role and everything it grants goes away. This cannot be '
                    'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final message = await ref.read(adminServiceProvider).deleteRole(role.id);
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? '${role.displayName} deleted.')),
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

/// The pinned strip: the running count and the search box. Painted in the
/// sheet's own colour so the groups scroll cleanly underneath it.
class _PermissionsBar extends SliverPersistentHeaderDelegate {
  const _PermissionsBar({
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

  /// Mirrors [controller]'s text purely so [shouldRebuild] can see it change
  /// — the delegate is rebuilt with a new instance, not listened to.
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
  bool shouldRebuild(_PermissionsBar old) =>
      old.selected != selected ||
      old.total != total ||
      old.query != query ||
      old.background != background ||
      old.controller != controller;
}

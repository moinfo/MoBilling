import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../config/app_config.dart';
import '../../navigation/menu.dart';
import '../../providers.dart';

/// The full staff menu, mirroring the web sidebar.
///
/// Five destinations also live on the bottom bar for one-tap reach; the drawer
/// is the complete tree. Entries are filtered twice: by the user's permissions
/// (same strings the API enforces) and by [MenuEntry.ready] — an entry with no
/// mobile screen yet is hidden rather than shown broken.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, this.onNavigate});

  /// Lets the shell switch bottom-bar tabs instead of pushing a route when the
  /// tapped destination is already one of them. Returns true if it handled it.
  final bool Function(String path)? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider);
    final auth = session.session;
    final user = session.user;

    final selfHosted = user?.tenant?.isSelfHosted ?? false;

    bool can(String permission) =>
        permission.isEmpty || (auth?.can(permission) ?? false);

    bool allowed(MenuEntry e) =>
        e.ready &&
        can(e.permission) &&
        (e.alsoRequires == null || can(e.alsoRequires!)) &&
        !(e.hideWhenSelfHosted && selfHosted);

    final coverage = staffMenuCoverage();

    final topInset = MediaQuery.paddingOf(context).top;

    return Drawer(
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Who's signed in, and for which tenant — on the same ink as the
            // masthead, so opening the menu extends it rather than replacing
            // it with a stock header.
            InkPanel(
              padding: EdgeInsets.fromLTRB(
                Spacing.md,
                topInset + Spacing.md,
                Spacing.md,
                Spacing.md,
              ),
              child: Row(
                children: [
                  InkAvatar(name: user?.name ?? '', onTap: null),
                  const SizedBox(width: Spacing.md - 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.tenant?.name ?? AppConfig.appName,
                          style: Type.display(17, color: Colors.white),
                          // Tenant names run long ("… Company Limited");
                          // wrapping beats an ellipsis in the one place the
                          // name is allowed to take room.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user?.name ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: InkPanel.bodyText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: Spacing.sm),
                children: [
                  for (final node in staffMenu)
                    switch (node) {
                      MenuLeaf(:final entry) =>
                        allowed(entry)
                            ? _tile(context, entry)
                            : const SizedBox.shrink(),
                      // Section shows when at least one child is visible —
                      // matching the web's canAny([...]) gating, without a
                      // separate permission to keep in sync.
                      MenuGroup(:final section) => () {
                        final visible = section.children
                            .where(allowed)
                            .toList();
                        if (visible.isEmpty) return const SizedBox.shrink();
                        return ExpansionTile(
                          leading: Icon(section.icon, size: 22),
                          title: Text(section.label),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          children: [
                            for (final entry in visible)
                              _tile(context, entry, inset: true),
                          ],
                        );
                      }(),
                    },
                ],
              ),
            ),

            const Divider(height: 1),
            // Honest coverage counter: this app deliberately does not carry
            // every web screen yet, and hiding that would be worse than
            // showing it.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.xs,
              ),
              child: Text(
                '${coverage.ready} of ${coverage.total} modules available on mobile',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'Sign out',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () {
                Navigator.of(context).pop();
                ref.read(sessionControllerProvider).logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, MenuEntry entry, {bool inset = false}) {
    return ListTile(
      leading: Padding(
        padding: EdgeInsets.only(left: inset ? Spacing.md : 0),
        child: Icon(entry.icon, size: 22),
      ),
      title: Text(entry.label),
      onTap: () {
        Navigator.of(context).pop();
        // Prefer switching the bottom-bar tab when the destination is one of
        // them — pushing a duplicate route would break back-navigation.
        if (onNavigate?.call(entry.path) ?? false) return;
        context.push(entry.path);
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../features/portal/portal_providers.dart';
import '../features/portal/portal_routes.dart';
import '../providers.dart';
import '../router.dart';
import 'shell.dart';
import 'tabs.dart';

/// The bottom bar, hoisted out of the home screen so it survives navigation.
///
/// It is installed via `MaterialApp.builder`, which puts it *outside* the
/// navigator. That is the whole point: previously the bar belonged to the home
/// route, so opening anything from the drawer — Team, Roles, Expenses — left
/// the user on a screen whose only way out was the back arrow. Now every
/// screen in a shell keeps its bar, and tapping a destination returns home on
/// that tab.
///
/// Deliberately not shown for the platform-admin shell, which is a single
/// scrolling console with no tabs, nor on the auth screens.
class AppChrome extends ConsumerWidget {
  const AppChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final shell = session.session.shell;

    if (session.status != SessionStatus.authenticated &&
        session.status != SessionStatus.expired) {
      return child;
    }

    final (tabs, index, onSelect) = switch (shell) {
      AppShell.staff => (
        staffTabs(session.session),
        ref.watch(staffTabProvider),
        (int i) => ref.read(staffTabProvider.notifier).state = i,
      ),
      AppShell.portal => (
        portalTabs(),
        ref.watch(portalTabProvider),
        (int i) => ref.read(portalTabProvider.notifier).state = i,
      ),
      // The admin console has no tabs to switch between.
      AppShell.admin => (const <TabSpec>[], 0, null),
    };

    if (tabs.length < 2 || onSelect == null) return child;

    final home = shell == AppShell.portal ? PortalRoutes.home : Routes.home;

    return Column(
      children: [
        Expanded(
          // The bar already covers the home-indicator inset, so the screens
          // above it must not pad for it a second time.
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: child,
          ),
        ),
        ShellNavBar(
          selectedIndex: index.clamp(0, tabs.length - 1),
          onSelected: (i) {
            onSelect(i);
            // A sheet or dialog is pushed imperatively onto GoRouter's page
            // Navigator, outside its declarative page list — so `router.go`
            // below swaps the page underneath it without ever closing it.
            // Left open, it keeps covering the new page and swallowing every
            // tap, including this one on a second press.
            //
            // This must go through `rootNavigatorKey`, not
            // `Navigator.of(context, rootNavigator: true)`: `context` here
            // is `AppChrome`'s own — installed via `MaterialApp.builder`, it
            // sits *outside* go_router's Navigator (which is rendered inside
            // the `child` this widget was handed, i.e. below this context in
            // the tree, not above it). `Navigator.of` only searches
            // ancestors, so from here it can never find that Navigator.
            rootNavigatorKey.currentState?.popUntil(
              (route) => route is! PopupRoute,
            );
            // From a pushed screen this is also the way back: switching
            // section should land on that section, not stack it on top of
            // whatever the user was reading.
            final router = ref.read(routerProvider);
            if (router.routerDelegate.currentConfiguration.uri.path != home) {
              router.go(home);
            }
          },
          items: [
            for (final t in tabs)
              ShellNavItem(
                icon: t.destination.icon,
                selectedIcon: t.destination.selectedIcon ?? t.destination.icon,
                label: t.destination.label,
              ),
          ],
        ),
      ],
    );
  }
}

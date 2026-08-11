import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

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
        Expanded(child: child),
        NavigationBar(
          selectedIndex: index.clamp(0, tabs.length - 1),
          onDestinationSelected: (i) {
            onSelect(i);
            // From a pushed screen this is also the way back: switching
            // section should land on that section, not stack it on top of
            // whatever the user was reading.
            final router = ref.read(routerProvider);
            if (router.routerDelegate.currentConfiguration.uri.path != home) {
              router.go(home);
            }
          },
          destinations: [for (final t in tabs) t.destination],
        ),
      ],
    );
  }
}

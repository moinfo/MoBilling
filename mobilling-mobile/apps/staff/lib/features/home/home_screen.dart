import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

import '../../providers.dart';
import '../auth/session_expired_sheet.dart';
import 'app_drawer.dart';
import '../clients/clients_tab.dart';
import '../dashboard/dashboard_tab.dart';
import '../documents/documents_tab.dart';
import '../payments/payments_tab.dart';
import '../tickets/tickets_tab.dart';

/// The staff shell. Tabs are filtered by the signed-in user's role
/// permissions (from the login response), so a cashier without tickets.read
/// never sees a Tickets tab that would only 403.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;
  bool _promptOpen = false;

  Future<void> _promptReauthentication() async {
    if (_promptOpen) return;
    _promptOpen = true;
    try {
      await SessionExpiredSheet.show(context);
    } finally {
      _promptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final auth = session.session;

    ref.listen<SessionStatus>(sessionStatusProvider, (previous, next) {
      if (next == SessionStatus.expired) _promptReauthentication();
    });

    // Dashboard is always present (the endpoint self-censors per metric);
    // the rest appear only with their read permission.
    final tabs = <(String, Widget, NavigationDestination)>[
      (
        'Dashboard',
        const DashboardTab(),
        const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard'),
      ),
      if (auth?.can(Permissions.clientsRead) ?? false)
        (
          'Clients',
          const ClientsTab(),
          const NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Clients'),
        ),
      if (auth?.can(Permissions.documentsRead) ?? false)
        (
          'Invoices',
          const DocumentsTab(),
          const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Invoices'),
        ),
      if (auth?.can(Permissions.paymentsRead) ?? false)
        (
          'Payments',
          const PaymentsTab(),
          const NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments),
              label: 'Payments'),
        ),
      if (auth?.can(Permissions.ticketsRead) ?? false)
        (
          'Tickets',
          const TicketsTab(),
          const NavigationDestination(
              icon: Icon(Icons.support_agent_outlined),
              selectedIcon: Icon(Icons.support_agent),
              label: 'Tickets'),
        ),
    ];

    final tab = _tab.clamp(0, tabs.length - 1);

    return Scaffold(
      // The drawer carries the full web menu; the bottom bar is the shortcut
      // set. Tapping a drawer entry that IS a bottom tab switches to it rather
      // than pushing a second copy on the stack.
      drawer: AppDrawer(
        onNavigate: (path) {
          const tabPaths = {
            '/home': 'Dashboard',
            '/clients': 'Clients',
            '/invoices': 'Invoices',
            '/payments-in': 'Payments',
            '/tickets': 'Tickets',
          };
          final title = tabPaths[path];
          if (title == null) return false;
          final index = tabs.indexWhere((t) => t.$1 == title);
          if (index < 0) return false;
          setState(() => _tab = index);
          return true;
        },
      ),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tabs[tab].$1, style: theme.textTheme.titleMedium),
            if (user != null)
              Text(
                user.tenant?.name ?? user.name,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(sessionControllerProvider).logout(),
          ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: [for (final t in tabs) t.$2],
      ),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [for (final t in tabs) t.$3],
            ),
    );
  }
}

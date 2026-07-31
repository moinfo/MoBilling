import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

import '../../providers.dart';
import '../auth/session_expired_sheet.dart';
import '../billing/dashboard_tab.dart';
import '../billing/invoices_tab.dart';
import '../more/more_tab.dart';
import '../services/services_tab.dart';
import '../support/support_tab.dart';

/// The signed-in shell: bottom navigation over the billing tabs.
///
/// Also the single place that reacts to [SessionStatus.expired] — listening
/// here rather than per-screen means the re-authentication prompt appears
/// exactly once no matter which request triggered the 401.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;
  bool _promptOpen = false;

  static const _titles = ['Home', 'Invoices', 'Services', 'Support', 'More'];

  Future<void> _promptReauthentication() async {
    // Guard against a burst of parallel 401s stacking sheets.
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
    final user = ref.watch(currentUserProvider);
    final tenant = ref.watch(sessionControllerProvider).tenant;

    ref.listen<SessionStatus>(sessionStatusProvider, (previous, next) {
      if (next == SessionStatus.expired) _promptReauthentication();
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tab == 0 ? (tenant?.name ?? 'Client area') : _titles[_tab],
              style: theme.textTheme.titleMedium,
            ),
            if (_tab == 0 && user?.clientName != null)
              Text(
                user!.clientName!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
      // IndexedStack keeps each tab's scroll position and loaded pages alive
      // across switches — losing a half-scrolled invoice list on every tab
      // change would make pagination pointless.
      body: IndexedStack(
        index: _tab,
        children: const [
          DashboardTab(),
          InvoicesTab(),
          ServicesTab(),
          SupportTab(),
          MoreTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Invoices',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns),
            label: 'Services',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Support',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_outlined),
            selectedIcon: Icon(Icons.menu),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

import '../../navigation/tabs.dart';
import '../../providers.dart';
import '../auth/session_expired_sheet.dart';
import 'app_drawer.dart';

/// The staff shell. Tabs are filtered by the signed-in user's role
/// permissions (from the login response), so a cashier without tickets.read
/// never sees a Tickets tab that would only 403.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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

    final tabs = staffTabs(auth);

    final tab = ref.watch(staffTabProvider).clamp(0, tabs.length - 1);

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
          final index = tabs.indexWhere((t) => t.title == title);
          if (index < 0) return false;
          ref.read(staffTabProvider.notifier).state = index;
          return true;
        },
      ),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tabs[tab].title, style: theme.textTheme.titleMedium),
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
        children: [for (final t in tabs) t.screen],
      ),
    );
  }
}

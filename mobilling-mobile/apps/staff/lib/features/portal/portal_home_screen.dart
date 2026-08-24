import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../auth/account_sheet.dart';
import '../auth/session_expired_sheet.dart';
import 'billing/dashboard_tab.dart';
import 'billing/invoices_tab.dart';
import 'more_tab.dart';
import 'portal_providers.dart';
import 'services/services_tab.dart';
import 'support/support_tab.dart';

/// The signed-in shell: bottom navigation over the billing tabs.
///
/// Also the single place that reacts to [SessionStatus.expired] — listening
/// here rather than per-screen means the re-authentication prompt appears
/// exactly once no matter which request triggered the 401.
class PortalHomeScreen extends ConsumerStatefulWidget {
  const PortalHomeScreen({super.key});

  @override
  ConsumerState<PortalHomeScreen> createState() => _PortalHomeScreenState();
}

class _PortalHomeScreenState extends ConsumerState<PortalHomeScreen> {
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
    final user = ref.watch(currentUserProvider);
    final tenant = ref.watch(sessionControllerProvider).tenant;
    final tab = ref.watch(portalTabProvider);

    ref.listen<SessionStatus>(sessionStatusProvider, (previous, next) {
      if (next == SessionStatus.expired) _promptReauthentication();
    });

    return Scaffold(
      // Same masthead as the staff shell. On Home the title is the client's
      // own name — the screen is about their account, not about the tenant,
      // who already has the eyebrow.
      appBar: ShellTopBar(
        eyebrow: tenant?.name ?? 'Client area',
        title: tab == 0 ? (user?.clientName ?? _titles[0]) : _titles[tab],
        // Home continues the ink below the masthead with the balance panel.
        edge: tab != 0,
        trailing: user == null
            ? null
            : InkAvatar(
                name: user.name,
                onTap: () => AccountSheet.show(context),
              ),
      ),
      // IndexedStack keeps each tab's scroll position and loaded pages alive
      // across switches — losing a half-scrolled invoice list on every tab
      // change would make pagination pointless.
      body: IndexedStack(
        index: tab,
        children: const [
          DashboardTab(),
          InvoicesTab(),
          ServicesTab(),
          SupportTab(),
          MoreTab(),
        ],
      ),
    );
  }
}

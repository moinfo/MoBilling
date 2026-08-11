import 'package:flutter/material.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

import '../features/clients/clients_tab.dart';
import '../features/dashboard/dashboard_tab.dart';
import '../features/documents/documents_tab.dart';
import '../features/payments/payments_tab.dart';
import '../features/portal/billing/dashboard_tab.dart' as portal;
import '../features/portal/billing/invoices_tab.dart';
import '../features/portal/more_tab.dart';
import '../features/portal/services/services_tab.dart';
import '../features/portal/support/support_tab.dart';
import '../features/tickets/tickets_tab.dart';

/// One bottom-bar destination and the screen behind it.
///
/// The bar is rendered by [AppChrome], outside the navigator, while the screen
/// lives in the home route's IndexedStack. Both read this list, so a
/// permission that hides a tab hides its destination too — they cannot drift
/// into disagreeing about which index means what.
class TabSpec {
  const TabSpec({
    required this.title,
    required this.screen,
    required this.destination,
  });

  final String title;
  final Widget screen;
  final NavigationDestination destination;
}

/// Dashboard is always present — the endpoint self-censors per metric — and
/// the rest appear only with their read permission.
List<TabSpec> staffTabs(AuthSession? auth) => [
      const TabSpec(
        title: 'Dashboard',
        screen: DashboardTab(),
        destination: NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
          tooltip: '',
        ),
      ),
      if (auth?.can(Permissions.clientsRead) ?? false)
        const TabSpec(
          title: 'Clients',
          screen: ClientsTab(),
          destination: NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clients',
            tooltip: '',
          ),
        ),
      if (auth?.can(Permissions.documentsRead) ?? false)
        const TabSpec(
          title: 'Invoices',
          screen: DocumentsTab(),
          destination: NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Invoices',
            tooltip: '',
          ),
        ),
      if (auth?.can(Permissions.paymentsRead) ?? false)
        const TabSpec(
          title: 'Payments',
          screen: PaymentsTab(),
          destination: NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Payments',
            tooltip: '',
          ),
        ),
      if (auth?.can(Permissions.ticketsRead) ?? false)
        const TabSpec(
          title: 'Tickets',
          screen: TicketsTab(),
          destination: NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Tickets',
            tooltip: '',
          ),
        ),
    ];

/// The client area's five tabs. Every client sees all of them — the portal has
/// no per-user permissions beyond admin/viewer, which gates actions rather
/// than whole sections.
List<TabSpec> portalTabs() => const [
      TabSpec(
        title: 'Home',
        screen: portal.DashboardTab(),
        destination: NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
          tooltip: '',
        ),
      ),
      TabSpec(
        title: 'Invoices',
        screen: InvoicesTab(),
        destination: NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Invoices',
          tooltip: '',
        ),
      ),
      TabSpec(
        title: 'Services',
        screen: ServicesTab(),
        destination: NavigationDestination(
          icon: Icon(Icons.dns_outlined),
          selectedIcon: Icon(Icons.dns),
          label: 'Services',
          tooltip: '',
        ),
      ),
      TabSpec(
        title: 'Support',
        screen: SupportTab(),
        destination: NavigationDestination(
          icon: Icon(Icons.support_agent_outlined),
          selectedIcon: Icon(Icons.support_agent),
          label: 'Support',
          tooltip: '',
        ),
      ),
      TabSpec(
        title: 'More',
        screen: MoreTab(),
        destination: NavigationDestination(
          icon: Icon(Icons.menu),
          selectedIcon: Icon(Icons.menu_open),
          label: 'More',
          tooltip: '',
        ),
      ),
    ];

import 'package:flutter/material.dart';

/// The staff navigation tree, mirroring the web sidebar
/// (`mobilling-ui/src/components/Layout/AppShell.tsx`).
///
/// This is the single place that decides what a staff user can reach. Each
/// entry carries the SAME `menu.*` permission string the web shell uses, which
/// is in turn the string the route middleware enforces — so the drawer, the
/// web sidebar and the API authorization can't drift apart.
///
/// [ready] marks whether the mobile screen for that entry exists yet. Not-ready
/// entries are hidden rather than shown broken; flip the flag in the same
/// commit that registers the route, and the drawer picks it up.
class MenuEntry {
  const MenuEntry({
    required this.label,
    required this.icon,
    required this.path,
    required this.permission,
    this.ready = false,
  });

  final String label;
  final IconData icon;
  final String path;

  /// Empty means "no specific permission" — visible to any signed-in staff
  /// user (the web shell has a few of these under Reports).
  final String permission;

  final bool ready;
}

/// A collapsible group. Mirrors the web's `canAny([...children])` behaviour:
/// the section shows when at least one child is visible, so there is no
/// separate permission to keep in sync.
class MenuSection {
  const MenuSection({
    required this.label,
    required this.icon,
    required this.children,
  });

  final String label;
  final IconData icon;
  final List<MenuEntry> children;
}

/// Either a leaf entry or a section.
sealed class MenuNode {
  const MenuNode();
}

class MenuLeaf extends MenuNode {
  const MenuLeaf(this.entry);
  final MenuEntry entry;
}

class MenuGroup extends MenuNode {
  const MenuGroup(this.section);
  final MenuSection section;
}

/// The full tree, in web sidebar order.
///
/// Entries with `ready: true` have a mobile screen and a registered route.
/// Everything else is scaffolded here so the remaining work is a flag flip
/// plus a GoRoute — the navigation design does not need revisiting.
const List<MenuNode> staffMenu = [
  MenuLeaf(MenuEntry(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    path: '/home',
    permission: 'menu.dashboard',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Collection',
    icon: Icons.track_changes_outlined,
    path: '/collection',
    permission: 'menu.collection',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Follow-ups',
    icon: Icons.phone_in_talk_outlined,
    path: '/followups',
    permission: 'menu.followups',
    ready: true,
  )),
  MenuGroup(MenuSection(
    label: 'Hosting',
    icon: Icons.language_outlined,
    children: [
      MenuEntry(
        label: 'Accounts',
        icon: Icons.storage_outlined,
        path: '/hosting',
        permission: 'menu.hosting',
        ready: true,
      ),
      MenuEntry(
        label: 'Manage Services',
        icon: Icons.tune_outlined,
        path: '/hosting/services',
        permission: 'menu.hosting',
      ),
    ],
  )),
  MenuLeaf(MenuEntry(
    label: 'Domains',
    icon: Icons.public_outlined,
    path: '/domains',
    permission: 'menu.domains',
        ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Support Tickets',
    icon: Icons.support_agent_outlined,
    path: '/tickets',
    permission: 'menu.tickets',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Canned Replies',
    icon: Icons.quickreply_outlined,
    path: '/canned-replies',
    permission: 'menu.tickets',
        ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Announcements',
    icon: Icons.campaign_outlined,
    path: '/announcements',
    permission: 'menu.announcements',
        ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Knowledgebase',
    icon: Icons.menu_book_outlined,
    path: '/knowledgebase',
    permission: 'menu.announcements',
        ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Satisfaction Calls',
    icon: Icons.favorite_outline,
    path: '/satisfaction-calls',
    permission: 'menu.satisfaction_calls',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Appointments',
    icon: Icons.event_outlined,
    path: '/appointments',
    permission: 'menu.satisfaction_calls',
    ready: true,
  )),
  MenuGroup(MenuSection(
    label: 'Billing',
    icon: Icons.description_outlined,
    children: [
      MenuEntry(
        label: 'Clients',
        icon: Icons.people_outline,
        path: '/clients',
        permission: 'menu.clients',
        ready: true,
      ),
      MenuEntry(
        label: 'Products & Services',
        icon: Icons.inventory_2_outlined,
        path: '/products',
        permission: 'menu.products',
        ready: true,
      ),
      MenuEntry(
        label: 'Product Add-ons',
        icon: Icons.add_box_outlined,
        path: '/product-addons',
        permission: 'menu.products',
        ready: true,
      ),
      MenuEntry(
        label: 'Configurable Options',
        icon: Icons.settings_input_component_outlined,
        path: '/config-options',
        permission: 'menu.products',
        ready: true,
      ),
      MenuEntry(
        label: 'Promotions / Coupons',
        icon: Icons.local_offer_outlined,
        path: '/coupons',
        permission: 'menu.products',
        ready: true,
      ),
      MenuEntry(
        label: 'Quotations',
        icon: Icons.request_quote_outlined,
        path: '/quotations',
        permission: 'menu.quotations',
        ready: true,
      ),
      MenuEntry(
        label: 'Proforma Invoices',
        icon: Icons.article_outlined,
        path: '/proformas',
        permission: 'menu.proformas',
        ready: true,
      ),
      MenuEntry(
        label: 'Invoices',
        icon: Icons.receipt_long_outlined,
        path: '/invoices',
        permission: 'menu.invoices',
        ready: true,
      ),
      MenuEntry(
        label: 'Credit Notes',
        icon: Icons.receipt_outlined,
        path: '/credit-notes',
        permission: 'menu.invoices',
        ready: true,
      ),
      MenuEntry(
        label: 'Payments',
        icon: Icons.payments_outlined,
        path: '/payments-in',
        permission: 'menu.payments_in',
        ready: true,
      ),
      MenuEntry(
        label: 'Subscriptions',
        icon: Icons.autorenew_outlined,
        path: '/subscriptions',
        permission: 'menu.client_subscriptions',
        ready: true,
      ),
      MenuEntry(
        label: 'Record a Payment',
        icon: Icons.add_card_outlined,
        path: '/payments/record',
        // Mobile-only shortcut: on the web this lives inside the Payments
        // page as a modal, but it is the action staff most need on a phone.
        permission: 'payments_in.create',
        ready: true,
      ),
      MenuEntry(
        label: 'Next Bills',
        icon: Icons.event_repeat_outlined,
        path: '/next-bills',
        permission: 'menu.next_bills',
        ready: true,
      ),
    ],
  )),
  MenuGroup(MenuSection(
    label: 'Statutory',
    icon: Icons.event_available_outlined,
    children: [
      MenuEntry(
        label: 'Obligations',
        icon: Icons.gavel_outlined,
        path: '/statutory',
        permission: 'menu.statutories',
        ready: true,
      ),
      MenuEntry(
        label: 'Schedule',
        icon: Icons.calendar_month_outlined,
        path: '/statutory-schedule',
        permission: 'menu.statutories',
        ready: true,
      ),
      MenuEntry(
        label: 'Bills',
        icon: Icons.request_page_outlined,
        path: '/bills',
        permission: 'menu.statutory_bills',
        ready: true,
      ),
      MenuEntry(
        label: 'Bill Categories',
        icon: Icons.category_outlined,
        path: '/bill-categories',
        permission: 'menu.bill_categories',
        ready: true,
      ),
      MenuEntry(
        label: 'Payment History',
        icon: Icons.history_outlined,
        path: '/payments-out',
        permission: 'menu.payments_out',
        ready: true,
      ),
    ],
  )),
  MenuGroup(MenuSection(
    label: 'Expenses',
    icon: Icons.account_balance_wallet_outlined,
    children: [
      MenuEntry(
        label: 'Expenses',
        icon: Icons.money_off_outlined,
        path: '/expenses',
        permission: 'menu.expenses',
        ready: true,
      ),
      MenuEntry(
        label: 'Categories',
        icon: Icons.category_outlined,
        path: '/expense-categories',
        permission: 'menu.expense_categories',
        ready: true,
      ),
      MenuEntry(
        label: 'Petty Cash',
        icon: Icons.savings_outlined,
        path: '/petty-cash',
        permission: 'menu.petty_cash',
        ready: true,
      ),
    ],
  )),
  MenuLeaf(MenuEntry(
    label: 'System Records',
    icon: Icons.dns_outlined,
    path: '/system-records',
    permission: 'menu.system_records',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'My Verifications',
    icon: Icons.verified_user_outlined,
    path: '/my-verifications',
    permission: 'menu.my_verifications',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Reports',
    icon: Icons.bar_chart_outlined,
    path: '/reports',
    permission: 'menu.reports',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'SMS',
    icon: Icons.sms_outlined,
    path: '/sms',
    permission: 'menu.sms',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Broadcast',
    icon: Icons.podcasts_outlined,
    path: '/broadcast',
    permission: 'menu.broadcast',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'WhatsApp',
    icon: Icons.chat_outlined,
    path: '/whatsapp',
    permission: 'menu.whatsapp',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Field Marketing',
    icon: Icons.place_outlined,
    path: '/field-marketing',
    permission: 'menu.field_marketing',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Social Media',
    icon: Icons.share_outlined,
    path: '/social-media',
    permission: 'menu.social_media',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Served Customers',
    icon: Icons.how_to_reg_outlined,
    path: '/served-customers',
    permission: 'menu.served_customers',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Staff Reports',
    icon: Icons.assignment_outlined,
    path: '/staff-reports',
    permission: 'menu.staff_reports',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Attendance',
    icon: Icons.fact_check_outlined,
    path: '/attendance',
    // The web gates this on attendance.manage, not a menu.* string.
    permission: 'attendance.manage',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Staff Targets',
    icon: Icons.flag_outlined,
    path: '/staff-targets',
    permission: 'menu.staff_targets',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Subscription',
    icon: Icons.card_membership_outlined,
    path: '/subscription',
    permission: 'menu.subscription',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Automation',
    icon: Icons.smart_toy_outlined,
    path: '/automation',
    permission: 'menu.automation',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Team',
    icon: Icons.groups_outlined,
    path: '/team',
    permission: 'settings.users',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Roles',
    icon: Icons.shield_outlined,
    path: '/roles',
    permission: 'settings.users',
    ready: true,
  )),
  MenuLeaf(MenuEntry(
    label: 'Settings',
    icon: Icons.settings_outlined,
    path: '/settings',
    permission: 'menu.settings',
    ready: true,
  )),
];

/// How many menu destinations are implemented vs defined — surfaced in the
/// drawer footer so it is always obvious what this build actually covers.
({int ready, int total}) staffMenuCoverage() {
  var ready = 0;
  var total = 0;
  for (final node in staffMenu) {
    final entries = switch (node) {
      MenuLeaf(:final entry) => [entry],
      MenuGroup(:final section) => section.children,
    };
    for (final entry in entries) {
      total++;
      if (entry.ready) ready++;
    }
  }
  return (ready: ready, total: total);
}

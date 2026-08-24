import 'package:flutter/material.dart';

/// Route paths for the platform super-admin shell.
///
/// All under `/admin`, matching the API prefix guarded by `EnsureSuperAdmin`
/// — so the router's cross-shell guard needs only a prefix test.
abstract final class AdminRoutes {
  static const home = '/admin';
  static const tenants = '/admin/tenants';
  static const permissions = '/admin/permissions';
  static const roleTemplates = '/admin/role-templates';
  static const plans = '/admin/plans';
  static const currencies = '/admin/currencies';
  static const smsPackages = '/admin/sms-packages';
  static const smsPurchases = '/admin/sms-purchases';
  static const licenses = '/admin/licenses';
  static const licensePlans = '/admin/license-plans';
  static const releases = '/admin/releases';
  static const settings = '/admin/settings';

  static String tenantPath(String id) => '/admin/tenants/$id';
  static String tenantEmailPath(String id) => '/admin/tenants/$id/email';
  static String tenantSmsPath(String id) => '/admin/tenants/$id/sms';
  static String tenantTemplatesPath(String id) =>
      '/admin/tenants/$id/templates';
}

/// One drawer destination in the admin shell.
class AdminMenuEntry {
  const AdminMenuEntry({
    required this.label,
    required this.icon,
    required this.path,
    this.subtitle,
  });

  final String label;
  final IconData icon;
  final String path;
  final String? subtitle;
}

/// The admin menu, mirroring the web's AdminShell.
///
/// No permission gating here: reaching this shell already required
/// `role === 'super_admin'`, and a super admin holds `['*']`. Gating each row
/// would imply a distinction that does not exist.
///
/// Email Settings, Email Templates and SMS Settings are per-tenant on the web
/// too — they are reached through a tenant, not from the top level, so they
/// live on the tenant detail screen rather than as drawer entries.
const List<AdminMenuEntry> adminMenu = [
  AdminMenuEntry(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    path: AdminRoutes.home,
    subtitle: 'Platform totals and SMS revenue',
  ),
  AdminMenuEntry(
    label: 'Tenants',
    icon: Icons.apartment_outlined,
    path: AdminRoutes.tenants,
    subtitle: 'Accounts, users, subscriptions, email & SMS',
  ),
  AdminMenuEntry(
    label: 'Subscription Plans',
    icon: Icons.card_membership_outlined,
    path: AdminRoutes.plans,
    subtitle: 'What tenants can buy',
  ),
  AdminMenuEntry(
    label: 'SMS Packages',
    icon: Icons.sell_outlined,
    path: AdminRoutes.smsPackages,
    subtitle: 'Credit bundles and pricing',
  ),
  AdminMenuEntry(
    label: 'SMS Purchases',
    icon: Icons.receipt_long_outlined,
    path: AdminRoutes.smsPurchases,
    subtitle: 'Orders awaiting confirmation',
  ),
  AdminMenuEntry(
    label: 'Licenses',
    icon: Icons.vpn_key_outlined,
    path: AdminRoutes.licenses,
    subtitle: 'Self-hosted install keys, WHMCS-style',
  ),
  AdminMenuEntry(
    label: 'License Plans',
    icon: Icons.vpn_key_outlined,
    path: AdminRoutes.licensePlans,
    subtitle: 'Pricing for self-hosted installs',
  ),
  AdminMenuEntry(
    label: 'Releases',
    icon: Icons.rocket_launch_outlined,
    path: AdminRoutes.releases,
    subtitle: '"Check for updates" catalog',
  ),
  AdminMenuEntry(
    label: 'Currencies',
    icon: Icons.currency_exchange_outlined,
    path: AdminRoutes.currencies,
  ),
  AdminMenuEntry(
    label: 'Permissions',
    icon: Icons.key_outlined,
    path: AdminRoutes.permissions,
    subtitle: 'The catalogue tenant roles are built from',
  ),
  AdminMenuEntry(
    label: 'Role Templates',
    icon: Icons.shield_outlined,
    path: AdminRoutes.roleTemplates,
    subtitle: 'Roles new tenants start with',
  ),
  AdminMenuEntry(
    label: 'Platform Settings',
    icon: Icons.settings_outlined,
    path: AdminRoutes.settings,
  ),
];

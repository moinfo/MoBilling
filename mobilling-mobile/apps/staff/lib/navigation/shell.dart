import 'package:mobilling_auth/mobilling_auth.dart';

/// Which of the three shells a signed-in session belongs in.
///
/// One app, three audiences. The decision is made once, here, from the login
/// response — `/auth/login` resolves the identifier against the staff `User`
/// table then `ClientUser`, and reports which matched via `user_type`.
enum AppShell {
  /// A client of the tenant: invoices, payments, services, support.
  portal,

  /// Tenant staff: the operational app.
  staff,

  /// Platform super admin: tenants, plans, platform settings.
  ///
  /// Deliberately its own shell rather than a permission on the staff one —
  /// a super admin has **no tenant**, and the staff dashboard, subscription
  /// banner and every `BelongsToTenant` query assume one.
  admin,
}

extension AppShellForSession on AuthSession? {
  AppShell get shell {
    final session = this;
    if (session == null) return AppShell.portal;

    if (session.user.userType == UserType.client) return AppShell.portal;

    // Super admins come back as user_type 'tenant' with permissions ['*'],
    // so the role is what separates them — not the permission set, which
    // would also match a fully-privileged tenant admin.
    return session.user.isSuperAdmin ? AppShell.admin : AppShell.staff;
  }
}

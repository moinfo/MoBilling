/// Which side of the platform a token belongs to.
///
/// `POST /api/auth/login` tries the staff `User` table and then the
/// `ClientUser` table, and reports which one matched via `user_type`. The two
/// are separate Authenticatables guarded by `ClientPortalMiddleware`, so a
/// token from one can never reach the other's routes.
enum UserType {
  client,
  tenant;

  static UserType fromJson(String? value) =>
      value == 'tenant' ? UserType.tenant : UserType.client;

  String toJson() => name;
}

/// The tenant (service provider) a signed-in client belongs to.
///
/// The mobile app is a single MoBilling-branded build, so unlike the web
/// portal it cannot resolve a tenant from the hostname. It does not need to:
/// the `ClientUser` carries its `tenant_id`, so branding arrives with the
/// login response and the app themes itself *after* sign-in.
class AuthTenant {
  const AuthTenant({
    required this.id,
    required this.name,
    this.logoUrl,
    this.website,
    this.currency,
    this.isSelfHosted = false,
  });

  final String id;
  final String name;
  final String? logoUrl;
  final String? website;

  /// Per-tenant billing currency (`tenants.currency`), e.g. 'TZS' or 'KES'.
  /// Not a platform constant — one build serves tenants on either.
  final String? currency;

  /// A licensed install running on the tenant's own server. Such a tenant
  /// has no MoBilling subscription to manage — the web shell hides the
  /// Subscription menu for them, and the staff drawer does the same.
  final bool isSelfHosted;

  factory AuthTenant.fromJson(Map<String, dynamic> json) => AuthTenant(
    id: json['id'].toString(),
    name: json['name']?.toString() ?? 'MoBilling',
    logoUrl: json['logo_url']?.toString(),
    website: json['website']?.toString(),
    currency: json['currency']?.toString(),
    isSelfHosted: switch (json['is_self_hosted']) {
      bool v => v,
      num v => v != 0,
      '1' || 'true' => true,
      _ => false,
    },
  );
}

/// The signed-in principal. Covers both `ClientUser` and staff `User`, since
/// the two share every field the shell needs.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.userType,
    this.email,
    this.phone,
    this.role,
    this.clientId,
    this.clientName,
    this.tenant,
  });

  final String id;
  final String name;
  final UserType userType;
  final String? email;
  final String? phone;

  /// For portal users this is 'admin' or 'user'; `isPortalAdmin()` on the
  /// backend is just `role == 'admin'`, and it gates sub-user management.
  final String? role;

  final String? clientId;
  final String? clientName;
  final AuthTenant? tenant;

  /// Portal admins may add and remove other portal users for their company.
  bool get isPortalAdmin => userType == UserType.client && role == 'admin';

  /// Platform super admin — `User::isSuperAdmin()` is `role === 'super_admin'`.
  ///
  /// Checked by role rather than by permissions: the login response gives a
  /// super admin `['*']`, but so could a fully-privileged tenant admin, and
  /// only the real super admin has no tenant and reaches `/admin/*`.
  bool get isSuperAdmin => userType == UserType.tenant && role == 'super_admin';

  factory AuthUser.fromJson(
    Map<String, dynamic> json, {
    required UserType userType,
  }) {
    final client = json['client'];
    final tenant = json['tenant'];

    return AuthUser(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      userType: userType,
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      role: json['role'] is String ? json['role'] as String : null,
      clientId: json['client_id']?.toString(),
      clientName: client is Map ? client['name']?.toString() : null,
      tenant: tenant is Map
          ? AuthTenant.fromJson(Map<String, dynamic>.from(tenant))
          : null,
    );
  }
}

/// A successful sign-in: who, what token, and what they may do.
class AuthSession {
  const AuthSession({
    required this.user,
    required this.token,
    this.permissions = const [],
  });

  final AuthUser user;
  final String token;

  /// Portal users get a fixed set ('portal.view', 'portal.profile', and
  /// 'portal.users' for admins). Staff get their role's real permission names,
  /// or `['*']` for super admins.
  final List<String> permissions;

  bool can(String permission) =>
      permissions.contains('*') || permissions.contains(permission);

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final userType = UserType.fromJson(json['user_type']?.toString());
    final rawPermissions = json['permissions'];

    return AuthSession(
      user: AuthUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map),
        userType: userType,
      ),
      token: json['token'].toString(),
      permissions: rawPermissions is List
          ? rawPermissions.map((p) => p.toString()).toList()
          : const [],
    );
  }
}

/// The 449 handshake: the identifier matched a client who has no portal login
/// yet, so the backend emailed (and possibly SMS'd) a six-digit code and is
/// waiting for it. Not a failure — the next step is
/// `POST /api/portal/verify-register`.
class OtpChallenge {
  const OtpChallenge({required this.message, this.clientName});

  final String message;
  final String? clientName;

  factory OtpChallenge.fromJson(Map<String, dynamic> json) => OtpChallenge(
    message:
        json['message']?.toString() ??
        'We sent a verification code to your email.',
    clientName: json['client_name']?.toString(),
  );
}

/// What a sign-in attempt produced: either a session, or an OTP challenge.
sealed class LoginOutcome {
  const LoginOutcome();
}

class LoginSucceeded extends LoginOutcome {
  const LoginSucceeded(this.session);
  final AuthSession session;
}

class LoginNeedsOtp extends LoginOutcome {
  const LoginNeedsOtp(this.challenge);
  final OtpChallenge challenge;
}

/// The password was right, but the account has a second factor.
///
/// `/auth/login` answers 200 with `requires_2fa` and a short-lived
/// `challenge_id` instead of a session; the session only exists after
/// `/auth/2fa/verify-login` accepts a code. Treating this as an outcome
/// rather than an error is what keeps the caller from mistaking a correct
/// password for a failed one.
class LoginNeedsTwoFactor extends LoginOutcome {
  const LoginNeedsTwoFactor({required this.challengeId, this.message});

  final String challengeId;

  /// The server's own prompt — it knows whether this is an authenticator
  /// app or something else.
  final String? message;
}

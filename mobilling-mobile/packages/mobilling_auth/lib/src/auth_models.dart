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
  });

  final String id;
  final String name;
  final String? logoUrl;
  final String? website;

  /// Per-tenant billing currency (`tenants.currency`), e.g. 'TZS' or 'KES'.
  /// Not a platform constant — one build serves tenants on either.
  final String? currency;

  factory AuthTenant.fromJson(Map<String, dynamic> json) => AuthTenant(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? 'MoBilling',
        logoUrl: json['logo_url']?.toString(),
        website: json['website']?.toString(),
        currency: json['currency']?.toString(),
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
        message: json['message']?.toString() ??
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

import 'package:mobilling_api/mobilling_api.dart';

import 'auth_models.dart';

/// Wraps the authentication endpoints.
///
/// Deliberately stateless — it performs calls and returns results. Deciding
/// what to *do* with a session (persist it, route on it, drop it) belongs to
/// `SessionController`, so this stays trivially testable.
class AuthService {
  const AuthService(this._api);

  final ApiClient _api;

  /// Sign in with an email address *or* a phone number.
  ///
  /// The backend resolves the identifier against staff users first, then
  /// portal users, then falls back to matching a client who has no portal
  /// account yet — which produces an OTP challenge rather than a session.
  /// Both outcomes are ordinary, hence [LoginOutcome].
  Future<LoginOutcome> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final body = await _api.post<Map<String, dynamic>>(
        '/auth/login',
        body: {'identifier': identifier.trim(), 'password': password},
      );
      return LoginSucceeded(AuthSession.fromJson(body));
    } on ApiException catch (e) {
      // 449 is the "we emailed you a code" handshake, not a failure.
      if (e.kind == ApiErrorKind.otpRequired) {
        final payload = e.body;
        return LoginNeedsOtp(
          OtpChallenge.fromJson(
            payload is Map ? Map<String, dynamic>.from(payload) : const {},
          ),
        );
      }
      rethrow;
    }
  }

  /// Ask for a fresh signup code. Throttled server-side per email per hour.
  ///
  /// Returns true when the address already has a portal account, in which case
  /// the caller should send the user to sign-in instead of registration.
  Future<bool> requestOtp(String email) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/request-otp',
      body: {'email': email.trim()},
    );
    return body['has_account'] == true;
  }

  /// Complete self-registration and receive a session.
  ///
  /// [company] names the client record for a brand-new signup; existing
  /// clients matched by email keep their own record and tenant.
  Future<AuthSession> verifyAndRegister({
    required String email,
    required String otp,
    required String name,
    required String password,
    String? phone,
    String? company,
    String? address,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/verify-register',
      body: {
        'email': email.trim(),
        'otp': otp.trim(),
        'name': name.trim(),
        'password': password,
        // Laravel's `confirmed` rule requires the matching field to be present.
        'password_confirmation': password,
        if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
        if (company != null && company.isNotEmpty) 'company': company.trim(),
        if (address != null && address.isNotEmpty) 'address': address.trim(),
      },
    );
    return AuthSession.fromJson(body);
  }

  /// Re-read the current principal, used to validate a restored token on cold
  /// start. Throws [ApiErrorKind.unauthenticated] if the token was revoked.
  Future<AuthSession> me(String token) async {
    final body = await _api.get<Map<String, dynamic>>('/auth/me');
    return AuthSession.fromJson({...body, 'token': token});
  }

  /// Revoke the current access token server-side.
  ///
  /// Sanctum tokens never expire on their own, so skipping this on sign-out
  /// would leave a valid credential alive indefinitely.
  Future<void> logout() => _api.post<dynamic>('/auth/logout');
}

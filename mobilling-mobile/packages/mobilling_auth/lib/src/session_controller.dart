import 'package:flutter/foundation.dart';
import 'package:mobilling_api/mobilling_api.dart';

import 'auth_models.dart';
import 'auth_service.dart';
import 'token_store.dart';

/// Where the app is in its authentication lifecycle.
enum SessionStatus {
  /// Cold start — we have not yet checked the keystore.
  unknown,

  /// Restoring and validating a stored token.
  restoring,

  /// Signed in and usable.
  authenticated,

  /// No valid session.
  signedOut,

  /// We hold a token the server has rejected, but we have not torn the session
  /// down yet. Whether this state is ever entered depends on the policy in
  /// [SessionController.handleUnauthenticated].
  expired,
}

/// Owns the signed-in session for the whole app.
///
/// A [ChangeNotifier] rather than anything fancier so it can drive
/// `go_router`'s `refreshListenable` directly — routing then follows session
/// state automatically instead of every screen guarding itself.
class SessionController extends ChangeNotifier {
  SessionController({
    required AuthService authService,
    required TokenStore tokenStore,
  })  : _auth = authService,
        _tokens = tokenStore;

  final AuthService _auth;
  final TokenStore _tokens;

  SessionStatus _status = SessionStatus.unknown;
  AuthSession? _session;

  SessionStatus get status => _status;
  AuthSession? get session => _session;
  AuthUser? get user => _session?.user;
  AuthTenant? get tenant => _session?.user.tenant;
  bool get isAuthenticated => _status == SessionStatus.authenticated;

  /// Read by the Dio interceptor on every request.
  Future<String?> readToken() => _tokens.read();

  void _setStatus(SessionStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  /// Cold start: restore a stored token and confirm the server still honours
  /// it. A token that was revoked (by staff, or by signing out elsewhere)
  /// looks identical to a valid one until we actually use it.
  Future<void> restore() async {
    _setStatus(SessionStatus.restoring);

    final token = await _tokens.read();
    if (token == null || token.isEmpty) {
      _setStatus(SessionStatus.signedOut);
      return;
    }

    try {
      _session = await _auth.me(token);
      _setStatus(SessionStatus.authenticated);
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthenticated ||
          e.kind == ApiErrorKind.forbidden) {
        await _clear();
        return;
      }
      // Offline on launch is not a reason to sign someone out — keep the token
      // and let individual screens surface their own network errors.
      _setStatus(SessionStatus.authenticated);
    }
  }

  Future<LoginOutcome> login({
    required String identifier,
    required String password,
  }) async {
    final outcome = await _auth.login(
      identifier: identifier,
      password: password,
    );
    if (outcome is LoginSucceeded) await _adopt(outcome.session);
    return outcome;
  }

  Future<void> register({
    required String email,
    required String otp,
    required String name,
    required String password,
    String? phone,
    String? company,
    String? address,
  }) async {
    final session = await _auth.verifyAndRegister(
      email: email,
      otp: otp,
      name: name,
      password: password,
      phone: phone,
      company: company,
      address: address,
    );
    await _adopt(session);
  }

  Future<void> _adopt(AuthSession session) async {
    _session = session;
    await _tokens.save(session.token, userType: session.user.userType.toJson());
    _setStatus(SessionStatus.authenticated);
  }

  /// Sign out deliberately. Revokes server-side first so the token cannot be
  /// replayed, but clears locally even if that call fails — the user asked to
  /// leave, and refusing would strand them.
  Future<void> logout() async {
    try {
      await _auth.logout();
    } on ApiException {
      // Best effort; local teardown below is what the user actually sees.
    }
    await _clear();
  }

  Future<void> _clear() async {
    _session = null;
    await _tokens.clear();
    _setStatus(SessionStatus.signedOut);
  }

  /// The 401 policy. Wired as the [ApiClient]'s `onUnauthenticated` handler,
  /// so it runs for every 401 from every request.
  ///
  /// We mark the session [SessionStatus.expired] rather than tearing it down.
  /// The web client hard-redirects to the login page on any 401
  /// (`mobilling-ui/src/api/axios.ts`), which is fine where reloading a page
  /// costs nothing — on mobile the same policy discards whatever the user was
  /// part-way through typing, with no way back.
  ///
  /// Deferring is safe here because nothing is actually protected client-side:
  /// every portal route re-authorises server-side on each call, so a session
  /// left visibly on screen can no longer *do* anything. Keeping the screen
  /// alive costs no access and preserves the user's work while they re-auth.
  ///
  /// A revoked Sanctum token never recovers — there is no refresh flow — so
  /// this is terminal for the credential, not a transient state to retry.
  Future<void> handleUnauthenticated(RequestOptions request) async {
    // Only a live session can expire. During [restore] the status is
    // `restoring` and that method does its own teardown; after sign-out there
    // is nothing left to expire. Guarding also means a burst of parallel
    // requests all 401-ing emits one notification, not one per request.
    if (_status != SessionStatus.authenticated) return;

    _setStatus(SessionStatus.expired);
  }

  /// Finish tearing down an [SessionStatus.expired] session — called when the
  /// user dismisses the re-authentication prompt instead of signing back in.
  ///
  /// No server call: the token that would authorise `/auth/logout` is the very
  /// one the server already rejected.
  Future<void> abandonExpiredSession() => _clear();
}

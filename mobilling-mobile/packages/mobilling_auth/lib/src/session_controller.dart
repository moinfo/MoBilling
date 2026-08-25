import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobilling_api/mobilling_api.dart';

import 'auth_models.dart';
import 'auth_service.dart';
import 'push_registration.dart';
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

  /// We hold a stored token but could not reach the server to validate it
  /// (no network, API down). Not signed out — the token is kept — but not
  /// usable either: without `/auth/me` we don't know who the token belongs
  /// to, so we cannot even pick the right shell. The splash offers retry or
  /// sign-out; see [SessionController.restoreError].
  offline,

  /// We hold a stored token whose owner asked for a biometric check before it
  /// is used. Nothing has been sent to the server yet; [SessionController.unlock]
  /// runs the normal restore once the device has verified the person.
  locked,

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
    PushRegistration pushRegistration = const NoopPushRegistration(),
  }) : _auth = authService,
       _tokens = tokenStore,
       _push = pushRegistration;

  final AuthService _auth;
  final TokenStore _tokens;
  final PushRegistration _push;

  SessionStatus _status = SessionStatus.unknown;
  AuthSession? _session;
  String? _restoreError;

  SessionStatus get status => _status;
  AuthSession? get session => _session;

  /// Why the last [restore] ended in [SessionStatus.offline]; null otherwise.
  String? get restoreError => _restoreError;
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
  Future<void> restore({bool unlocked = false}) async {
    _restoreError = null;
    _setStatus(SessionStatus.restoring);

    final token = await _tokens.read();
    if (token == null || token.isEmpty) {
      _setStatus(SessionStatus.signedOut);
      return;
    }

    // A biometric-locked session waits for the device to vouch for the
    // person before the token goes anywhere near the network.
    if (!unlocked && await _tokens.readBiometricLock()) {
      _setStatus(SessionStatus.locked);
      return;
    }

    try {
      _session = await _auth.me(token);
      _setStatus(SessionStatus.authenticated);
      // A stored session can outlive the device's last FCM token registration
      // (reinstall, cleared app data, a token the server never saw because
      // Firebase wasn't wired up yet) — re-assert it on every successful
      // restore rather than only at the moment of login.
      unawaited(_push.registerAfterLogin(_auth));
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthenticated ||
          e.kind == ApiErrorKind.forbidden) {
        await _clear();
        return;
      }
      // Offline on launch is not a reason to sign someone out — keep the
      // token. But it is not a session either: with no `/auth/me` response
      // there is no user, and an earlier version that reported
      // `authenticated` here dropped every launch into the client portal
      // shell (the null-session default) regardless of whose token it was.
      // In debug builds surface the underlying cause too — "could not reach"
      // hides whether it was a refused connection, a timeout, or a parse
      // failure, and on a dev box that is the whole question.
      _restoreError = kDebugMode && e.cause != null
          ? '${e.message}\n${e.cause}'
          : e.message;
      _setStatus(SessionStatus.offline);
    }
  }

  /// Drop the stored token without a server call — for a user stuck on
  /// [SessionStatus.offline] or [SessionStatus.locked] who would rather sign
  /// in afresh.
  Future<void> forgetStoredSession() => _clear();

  /// The device has verified the person: use the locked token now.
  Future<void> unlock() => restore(unlocked: true);

  /// Require (or stop requiring) a biometric check before the stored token
  /// is used on the next launch. The caller is responsible for having
  /// confirmed the device can actually do biometrics.
  Future<void> setBiometricLock(bool enabled) =>
      _tokens.setBiometricLock(enabled);

  Future<bool> biometricLockEnabled() => _tokens.readBiometricLock();

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

  /// Finish a login that stopped at the second factor. Adopting the session
  /// here rather than in the screen keeps every path into a signed-in state
  /// going through one place.
  Future<void> completeTwoFactorLogin({
    required String challengeId,
    String? code,
    String? recoveryCode,
  }) async {
    final session = await _auth.verifyTwoFactorLogin(
      challengeId: challengeId,
      code: code,
      recoveryCode: recoveryCode,
    );
    await _adopt(session);
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
    // Covers login, registration, impersonation and returning from it — every
    // path that lands on a new bearer token needs the device's push token
    // re-pointed at whoever now holds it.
    unawaited(_push.registerAfterLogin(_auth));
  }

  /// Sign out deliberately. Revokes server-side first so the token cannot be
  /// replayed, but clears locally even if that call fails — the user asked to
  /// leave, and refusing would strand them.
  Future<void> logout() async {
    // Must run before the token is revoked below — the DELETE call itself
    // needs to authenticate as the very session that's ending.
    try {
      await _push.unregisterBeforeLogout(_auth);
    } on ApiException {
      // Best effort; a stale token left registered costs one wasted push,
      // not a stuck sign-out.
    }
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

  // -------------------------------------------------------------------
  // Impersonation — a super admin viewing the app as a tenant's admin (or one
  // of its specific users). Mirrors the web's `admin_token` stash in
  // `AuthContext.tsx`'s `impersonate()`/`exitImpersonation()`: swapping in the
  // new session keeps the current one in memory so [exitImpersonation] can
  // restore it. Unlike the web, there is nothing persisted beyond this
  // running instance — the web's stash survives a page reload because
  // `localStorage` does; a killed app process loses it the same way the web
  // loses its own stash once nothing has it in memory any more, and the way
  // back is then what the web falls back to as well: sign out, sign back in
  // as super admin.
  // -------------------------------------------------------------------

  AuthSession? _preImpersonationSession;

  /// True once [impersonate] has swapped in someone else's session.
  bool get isImpersonating => _preImpersonationSession != null;

  /// Who [exitImpersonation] returns to — for a button that names its
  /// destination rather than just saying "back".
  String? get preImpersonationName => _preImpersonationSession?.user.name;

  /// Adopt [session] (an impersonated tenant admin or tenant user), keeping
  /// the current session so [exitImpersonation] can return to it later. A
  /// second call while already impersonating — e.g. drilling from the tenant
  /// admin into one of that tenant's own users — keeps the *original* session
  /// as the return target rather than the intermediate one, the same rule the
  /// web applies to `admin_token`.
  Future<void> impersonate(AuthSession session) async {
    _preImpersonationSession ??= _session;
    await _adopt(session);
    // The impersonation endpoints answer with no `permissions` field; refresh
    // from `/auth/me` under the new token, exactly as the web's `impersonate()`
    // does with its own follow-up `getMe()` call.
    try {
      _session = await _auth.me(session.token);
    } on ApiException {
      // Keep the coarser session from the impersonation response; not fatal.
    }
    // `_adopt` only notifies when [SessionStatus] itself changes, which it
    // doesn't here (already `authenticated`) — without this, nothing tells
    // the router the signed-in user (and therefore its shell) just changed.
    notifyListeners();
  }

  /// Return to the session [impersonate] stashed away. No-op if not currently
  /// impersonating.
  Future<void> exitImpersonation() async {
    final original = _preImpersonationSession;
    if (original == null) return;
    _preImpersonationSession = null;
    await _adopt(original);
    notifyListeners();
  }
}

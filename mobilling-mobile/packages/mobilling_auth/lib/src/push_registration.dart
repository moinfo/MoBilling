import 'auth_service.dart';

/// Device push-token lifecycle, called by [SessionController] at the exact
/// moments the signed-in identity changes.
///
/// Lives here (not in the app layer) so `SessionController` can own the call
/// sites without this package depending on Firebase — the concrete
/// implementation (which does) is provided by the app.
abstract class PushRegistration {
  Future<void> registerAfterLogin(AuthService auth);
  Future<void> unregisterBeforeLogout(AuthService auth);
}

/// Does nothing. The default until the app supplies a real implementation.
class NoopPushRegistration implements PushRegistration {
  const NoopPushRegistration();

  @override
  Future<void> registerAfterLogin(AuthService auth) async {}

  @override
  Future<void> unregisterBeforeLogout(AuthService auth) async {}
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

/// In-memory stand-in for the platform keystore.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage();

  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

/// Scripted AuthService — no HTTP.
class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(ApiClient(baseUrl: 'http://test', tokenReader: _noToken));

  static Future<String?> _noToken() async => null;

  LoginOutcome? nextLogin;
  Object? loginError;
  AuthSession? meResult;
  Object? meError;
  int logoutCalls = 0;

  @override
  Future<LoginOutcome> login({
    required String identifier,
    required String password,
  }) async {
    if (loginError != null) throw loginError!;
    return nextLogin!;
  }

  @override
  Future<AuthSession> me(String token) async {
    if (meError != null) throw meError!;
    return meResult!;
  }

  @override
  Future<void> logout() async => logoutCalls++;
}

AuthSession _session({String token = 'tok-1'}) => AuthSession(
      user: AuthUser.fromJson(
        const {
          'id': 'u1',
          'name': 'Asha',
          'email': 'asha@example.com',
          'role': 'admin',
          'tenant': {'id': 't1', 'name': 'Acme', 'currency': 'TZS'},
        },
        userType: UserType.client,
      ),
      token: token,
      permissions: const ['portal.view', 'portal.users'],
    );

ApiException _unauthorised() => ApiException(
      kind: ApiErrorKind.unauthenticated,
      message: 'Unauthenticated.',
      statusCode: 401,
    );

void main() {
  late _FakeAuthService auth;
  late _FakeSecureStorage storage;
  late SessionController controller;

  setUp(() {
    auth = _FakeAuthService();
    storage = _FakeSecureStorage();
    controller = SessionController(
      authService: auth,
      tokenStore: TokenStore(storage: storage),
    );
  });

  group('401 policy', () {
    test('defers teardown: marks expired and KEEPS the token and user', () async {
      auth.nextLogin = LoginSucceeded(_session());
      await controller.login(identifier: 'asha@example.com', password: 'pw');
      expect(controller.status, SessionStatus.authenticated);

      await controller.handleUnauthenticated(RequestOptions(path: '/portal/x'));

      // The whole point of the deferred policy: the user's context survives so
      // a re-auth sheet can overlay the screen they were working on.
      expect(controller.status, SessionStatus.expired);
      expect(controller.user, isNotNull);
      expect(await controller.readToken(), 'tok-1');
    });

    test('notifies listeners once for a burst of parallel 401s', () async {
      auth.nextLogin = LoginSucceeded(_session());
      await controller.login(identifier: 'asha@example.com', password: 'pw');

      var notifications = 0;
      controller.addListener(() => notifications++);

      await Future.wait([
        controller.handleUnauthenticated(RequestOptions(path: '/a')),
        controller.handleUnauthenticated(RequestOptions(path: '/b')),
        controller.handleUnauthenticated(RequestOptions(path: '/c')),
      ]);

      expect(controller.status, SessionStatus.expired);
      expect(notifications, 1);
    });

    test('is inert when there is no live session to expire', () async {
      expect(controller.status, SessionStatus.unknown);
      await controller.handleUnauthenticated(RequestOptions(path: '/a'));
      expect(controller.status, SessionStatus.unknown);
    });

    test('re-authenticating from expired restores the session', () async {
      auth.nextLogin = LoginSucceeded(_session());
      await controller.login(identifier: 'asha@example.com', password: 'pw');
      await controller.handleUnauthenticated(RequestOptions(path: '/a'));
      expect(controller.status, SessionStatus.expired);

      auth.nextLogin = LoginSucceeded(_session(token: 'tok-2'));
      await controller.login(identifier: 'asha@example.com', password: 'pw');

      expect(controller.status, SessionStatus.authenticated);
      expect(await controller.readToken(), 'tok-2');
    });

    test('abandoning an expired session clears the token', () async {
      auth.nextLogin = LoginSucceeded(_session());
      await controller.login(identifier: 'asha@example.com', password: 'pw');
      await controller.handleUnauthenticated(RequestOptions(path: '/a'));

      await controller.abandonExpiredSession();

      expect(controller.status, SessionStatus.signedOut);
      expect(controller.user, isNull);
      expect(await controller.readToken(), isNull);
    });
  });

  group('restore', () {
    test('signs out when the stored token was revoked', () async {
      await TokenStore(storage: storage).save('stale', userType: 'client');
      auth.meError = _unauthorised();

      await controller.restore();

      expect(controller.status, SessionStatus.signedOut);
      expect(storage.values, isEmpty);
    });

    test('keeps the session when the device is merely offline', () async {
      await TokenStore(storage: storage).save('tok-1', userType: 'client');
      auth.meError = ApiException(
        kind: ApiErrorKind.network,
        message: 'No internet connection.',
      );

      await controller.restore();

      // Launching in a tunnel is not a reason to sign someone out.
      expect(controller.status, SessionStatus.authenticated);
      expect(await controller.readToken(), 'tok-1');
    });

    test('goes straight to signed out with no stored token', () async {
      await controller.restore();
      expect(controller.status, SessionStatus.signedOut);
    });
  });

  group('logout', () {
    test('clears locally even when the server call fails', () async {
      auth.nextLogin = LoginSucceeded(_session());
      await controller.login(identifier: 'asha@example.com', password: 'pw');

      await controller.logout();

      expect(controller.status, SessionStatus.signedOut);
      expect(await controller.readToken(), isNull);
      expect(auth.logoutCalls, 1);
    });
  });

  group('login outcomes', () {
    test('an OTP challenge does not create a session', () async {
      auth.nextLogin = const LoginNeedsOtp(
        OtpChallenge(message: 'Code sent.', clientName: 'Acme Ltd'),
      );

      final outcome =
          await controller.login(identifier: 'new@example.com', password: 'pw');

      expect(outcome, isA<LoginNeedsOtp>());
      expect(controller.status, SessionStatus.unknown);
      expect(await controller.readToken(), isNull);
    });

    test('a successful login persists the token and user type', () async {
      auth.nextLogin = LoginSucceeded(_session());

      await controller.login(identifier: 'asha@example.com', password: 'pw');

      expect(controller.isAuthenticated, isTrue);
      expect(controller.tenant?.currency, 'TZS');
      expect(controller.user?.isPortalAdmin, isTrue);
      expect(storage.values['mobilling.auth.user_type'], 'client');
    });
  });
}

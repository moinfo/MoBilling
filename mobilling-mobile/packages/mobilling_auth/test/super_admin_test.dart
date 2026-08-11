import 'package:flutter_test/flutter_test.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

/// One login now serves three audiences, and `isSuperAdmin` is what separates
/// a platform admin from an ordinary tenant user. Getting it wrong would put
/// a super admin in a tenant-scoped shell (or worse, the reverse), so the
/// distinction is pinned here.
AuthUser _user({required String type, String? role}) => AuthUser.fromJson(
      {'id': 'u1', 'name': 'Test', 'role': role},
      userType: UserType.fromJson(type),
    );

void main() {
  group('AuthUser.isSuperAdmin', () {
    test('true only for a tenant user whose role is super_admin', () {
      expect(_user(type: 'tenant', role: 'super_admin').isSuperAdmin, isTrue);
    });

    test('an ordinary staff user is not a super admin', () {
      expect(_user(type: 'tenant', role: 'admin').isSuperAdmin, isFalse);
      expect(_user(type: 'tenant', role: null).isSuperAdmin, isFalse);
    });

    test('a client is never a super admin, whatever the role string says', () {
      // ClientUser.role is 'admin' | 'user' — a different vocabulary that
      // happens to share the word "admin".
      expect(_user(type: 'client', role: 'admin').isSuperAdmin, isFalse);
      expect(_user(type: 'client', role: 'super_admin').isSuperAdmin, isFalse);
    });

    test('portal admin and super admin are independent', () {
      final portalAdmin = _user(type: 'client', role: 'admin');
      expect(portalAdmin.isPortalAdmin, isTrue);
      expect(portalAdmin.isSuperAdmin, isFalse);

      final superAdmin = _user(type: 'tenant', role: 'super_admin');
      expect(superAdmin.isPortalAdmin, isFalse);
      expect(superAdmin.isSuperAdmin, isTrue);
    });
  });

  group('permissions vs role', () {
    test('holding * does not by itself make someone a super admin', () {
      // The login response gives a super admin ['*'], but a fully-privileged
      // tenant admin could hold it too — which is why the shell decision reads
      // the role, not the permission set.
      final session = AuthSession(
        user: _user(type: 'tenant', role: 'admin'),
        token: 'tok',
        permissions: const ['*'],
      );
      expect(session.can('anything.at.all'), isTrue);
      expect(session.user.isSuperAdmin, isFalse);
    });
  });
}

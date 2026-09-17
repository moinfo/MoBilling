import 'dart:io' show Platform;
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A stable per-install device identifier, for the backend's geofenced
/// self-check-in device binding (`AttendanceController::checkIn`): the
/// first check-in from this app binds this id to the signed-in user, and
/// every check-in after has to match it. Deliberately not the phone's real
/// hardware id (Android ID / identifierForVendor) — a self-generated one
/// resets cleanly on reinstall the same way the binding itself is meant to
/// be reset by an admin, rather than silently surviving a factory reset or
/// a different owner's reinstall.
class DeviceBinding {
  DeviceBinding({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _deviceIdKey = 'mobilling.attendance.device_id';

  String? _cachedId;

  Future<String> deviceId() async {
    if (_cachedId != null) return _cachedId!;
    var id = await _storage.read(key: _deviceIdKey);
    if (id == null || id.isEmpty) {
      id = _generateId();
      await _storage.write(key: _deviceIdKey, value: id);
    }
    _cachedId = id;
    return id;
  }

  /// "Samsung SM-A546E" / "iPhone15,2" — purely informational, shown to an
  /// admin resetting a binding so they know whose phone they're looking at.
  Future<String?> deviceModel() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return '${a.manufacturer} ${a.model}'.trim();
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return i.utsname.machine;
      }
    } catch (_) {
      // Best-effort only — never block a check-in over a label.
    }
    return null;
  }

  static String _generateId() {
    final random = Random.secure();
    // A v4-shaped UUID is not required by the backend (it just stores
    // whatever string this sends), but shaping it like one keeps it
    // recognisable next to real UUIDs if anyone ever reads the column.
    String hex(int bytes) => List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${hex(4)}-${hex(2)}-4${hex(2).substring(1)}-'
        '${(8 + random.nextInt(4)).toRadixString(16)}${hex(2).substring(1)}-'
        '${hex(6)}';
  }
}

final Provider<DeviceBinding> deviceBindingProvider = Provider<DeviceBinding>(
  (ref) => DeviceBinding(),
);

import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mobilling_auth/mobilling_auth.dart';

/// Developer hooks for reviewing screens on the simulator.
///
/// Simulator input automation is blocked on the dev Mac, so there is no way
/// to type credentials or tap through menus from a script. These two hooks
/// make every screen reachable anyway:
///
///   * `/tmp/mobilling_debug_token` (+ `/tmp/mobilling_debug_user_type`):
///     used as the stored session when the keychain has none, so a freshly
///     installed build is signed in without typing.
///   * `/tmp/mobilling_debug_route`: the screen to open on launch instead of
///     home (see `router.dart`).
///
/// Then `kill -USR2 <flutter_tools pid>` (hot restart) + `xcrun simctl io
/// booted screenshot`. Both hooks are compiled out of release builds and are
/// no-ops when the files are absent.
abstract final class DebugHooks {
  static String? readFile(String path) {
    if (!kDebugMode) return null;
    try {
      final value = File(path).readAsStringSync().trim();
      return value.isEmpty ? null : value;
    } on FileSystemException {
      return null;
    }
  }

  static String? get startRoute {
    final route = readFile('/tmp/mobilling_debug_route');
    return route != null && route.startsWith('/') ? route : null;
  }
}

/// A [TokenStore] that falls back to the debug token file when the keychain
/// is empty. Saving or clearing a real session behaves exactly as usual; the
/// fallback only fills the gap when nothing is stored.
class DebugTokenStore extends TokenStore {
  DebugTokenStore();

  @override
  Future<String?> read() async =>
      await super.read() ?? DebugHooks.readFile('/tmp/mobilling_debug_token');

  @override
  Future<String?> readUserType() async =>
      await super.readUserType() ??
      DebugHooks.readFile('/tmp/mobilling_debug_user_type');
}

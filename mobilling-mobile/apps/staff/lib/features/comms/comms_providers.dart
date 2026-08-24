import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

/// The one provider shared by all four comms screens; everything else is
/// declared next to the screen that reads it.
final Provider<CommsService> commsServiceProvider = Provider<CommsService>(
  (ref) => CommsService(ref.watch(apiClientProvider)),
);

/// Whether the signed-in user holds a permission. Super admins hold '*', which
/// `AuthSession.can` already accounts for.
///
/// Route-level gating happens in the navigation drawer; this is for hiding
/// individual actions inside a screen the user may otherwise read.
final ProviderFamily<bool, String> commsPermissionProvider =
    Provider.family<bool, String>(
      (ref, permission) =>
          ref.watch(sessionControllerProvider).session?.can(permission) ??
          false,
    );

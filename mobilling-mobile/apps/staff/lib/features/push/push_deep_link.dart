import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/shell.dart';

/// Routes a tapped push notification to the screen it's about.
///
/// Every notification class in the backend now pushes (see PUSH_SETUP.md),
/// spanning all three shells — so unlike the first cut of this file, a
/// `type` can no longer be assumed portal-only. [currentShell] resolves the
/// ambiguous ones (today: `ticket`, sent to both a portal client and staff).
/// Most of the ~20 push types added in that sweep have no mapping below yet
/// and simply no-op on tap rather than navigate anywhere — safe, but see
/// PUSH_SETUP.md for what's still unmapped.
void wirePushDeepLinks(GoRouter router, AppShell Function() currentShell) {
  void handle(RemoteMessage message) {
    final path = _pathFor(message.data, currentShell());
    if (path != null) router.push(path);
  }

  // Tapped while backgrounded.
  FirebaseMessaging.onMessageOpenedApp.listen(handle);
  // Tapped while terminated — the tap is what launched the app, so there's
  // no "opened" event to listen for; the message is handed back instead.
  FirebaseMessaging.instance.getInitialMessage().then((message) {
    if (message != null) handle(message);
  });
}

String? _pathFor(Map<String, dynamic> data, AppShell shell) {
  switch (data['type']) {
    // InvoiceSentNotification and its whole family (cancelled, overdue,
    // termination warning, recurring/bundled reminders) all target a
    // portal Client — never staff — so this stays unconditional.
    case 'invoice':
    case 'payment':
      final id = data['document_id'];
      return id == null ? null : '/portal/invoices/$id';
    // TicketRepliedNotification targets the portal client who filed the
    // ticket; TicketActivityStaffNotification targets the staff member
    // it's assigned to. Same `type`, different owner, different route.
    case 'ticket':
      final id = data['ticket_id'];
      if (id == null) return null;
      return shell == AppShell.portal ? '/portal/tickets/$id' : '/tickets/$id';
    default:
      return null;
  }
}

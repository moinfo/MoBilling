/// The in-app notification centre — mirrors web's `NotificationBell.tsx`.
///
/// Backed by Laravel's stock `Notifiable` trait (`NotificationController` does
/// no customisation at all: `$user->notifications()->paginate(...)`), so a row
/// is whatever a given `Notification::toDatabase()`/`toArray()` wrote,
/// wrapped in the columns Laravel adds itself (`id`, `type`, `read_at`,
/// `created_at`). Only notifications whose `via()` includes `'database'` ever
/// appear here — about half of the backend's 45 classes are push/mail/sms
/// only and never show up in this list.
///
/// The inner `data` map is NOT standardised across notification classes —
/// confirmed by reading every database-backed one:
///   * Every one but `TicketActivityStaffNotification` puts the navigation
///     target under `url`; that one alone uses `link` instead, and also omits
///     `type` and any id — a real, pre-existing backend inconsistency (web's
///     own bell can't navigate on it either). [target] reads both keys.
///   * `WelcomeNotification`'s `url` is `/dashboard`, the web route — there is
///     no such mobile route, so [target] remaps it to `/home`.
///   * `SmsActivationRequestNotification`'s `url` is a web-only
///     `?tenant=<id>` query string with no separate id field — [target]
///     leaves it as-is (a platform-admin, rarely-seen type); tapping it will
///     not resolve to a real mobile route today.
///   * The 5 newer business-event types (`order`, `payment_received`,
///     `hosting_upgrade`, `domain_renewal`, `cron_failure`) carry a `url` that
///     is web-correct but mobile-imprecise (e.g. `/invoices`, a bottom tab
///     with no direct path on mobile, not a pushable route) — [target]
///     prefers the id field each one also carries (`document_id`,
///     `hosting_account_id`, `domain_id`) to land on a real detail route
///     instead, matching the same per-type resolution
///     `features/push/push_deep_link.dart` does for the push payload.
library;

import '../json.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.data,
    this.dataType,
    this.url,
    this.readAt,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;

  /// The rest of `data`, for the id fields [target] needs per-type.
  final Map<String, dynamic> data;

  /// The inner `data.type`, e.g. `staff_target_assigned` — absent on
  /// `TicketActivityStaffNotification`. Not the same as the outer Laravel
  /// `type` column, which is the full PHP class name and not useful for
  /// display.
  final String? dataType;

  /// `data.url`, falling back to `data.link` for the one class that uses it.
  final String? url;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// The route to push on tap, or null when this notification carries no
  /// resolvable destination (a few are informational-only by design, e.g.
  /// OTP/password-reset alerts that never carry a link).
  String? get target {
    switch (dataType) {
      case 'order':
      case 'payment_received':
        final id = data['document_id'];
        return id == null ? null : '/documents/$id';
      case 'hosting_upgrade':
        return '/hosting';
      case 'domain_renewal':
        return '/domains';
      case 'cron_failure':
        return '/admin';
    }

    final raw = url;
    if (raw == null || raw.isEmpty) return null;
    if (raw == '/dashboard') return '/home';
    // Everything else is either already a real mobile path (the 20-odd
    // `/leave`, `/staff-targets`, `/bills`, `/tickets`-style list routes all
    // match 1:1) or a web-only query-string path this app has no route for
    // (`/admin/sms-settings?tenant=...`) — left as-is; a caller that pushes
    // an unknown path just gets go_router's own "page not found" behaviour
    // rather than mobile silently pretending to navigate somewhere real.
    return raw;
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? const <String, dynamic>{};
    return AppNotification(
      id: json.id(),
      title: data.strOr('title', 'Notification'),
      message: data.strOr('message', ''),
      createdAt: json.date('created_at') ?? DateTime.now(),
      data: data,
      dataType: data.str('type'),
      url: data.str('url') ?? data.str('link'),
      readAt: json.date('read_at'),
    );
  }
}

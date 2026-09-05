import '../api_client.dart';
import '../paginated.dart';
import 'notification_models.dart';

/// The in-app notification centre. No permission gate — every signed-in
/// staff/admin user has their own notifications; `NotificationController`
/// scopes everything to `$request->user()` itself.
class NotificationService {
  const NotificationService(this._api);

  final ApiClient _api;

  /// GET /notifications — Laravel's paginator verbatim, newest first.
  Future<Paginated<AppNotification>> notifications({
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/notifications',
      query: {'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, AppNotification.fromJson);
  }

  /// GET /notifications/unread-count — polled by the bell badge.
  Future<int> unreadCount() async {
    final body = await _api.get<Map<String, dynamic>>(
      '/notifications/unread-count',
    );
    return body['count'] is num ? (body['count'] as num).toInt() : 0;
  }

  /// PATCH /notifications/{id}/read.
  Future<void> markAsRead(String id) =>
      _api.patch<dynamic>('/notifications/$id/read');

  /// POST /notifications/mark-all-read.
  Future<void> markAllAsRead() =>
      _api.post<dynamic>('/notifications/mark-all-read');
}

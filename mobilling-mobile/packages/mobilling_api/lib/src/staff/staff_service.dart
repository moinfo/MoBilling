import '../api_client.dart';
import '../paginated.dart';
import '../portal/support_models.dart' show TicketReply;
import 'staff_models.dart';

/// Typed access to the tenant-side (staff) endpoints used by the staff app.
///
/// Every route here sits behind `permission:*` middleware — a 403 means the
/// signed-in user's role lacks that permission, and the app hides the
/// corresponding tab up-front via the permission names in [Permissions].
class StaffService {
  const StaffService(this._api);

  final ApiClient _api;

  /// GET /dashboard/summary — per-field permission-gated summary.
  Future<StaffDashboard> dashboard({int? month, int? year}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/dashboard/summary',
      query: {'month': month, 'year': year},
    );
    return StaffDashboard.fromJson(body);
  }

  /// GET /clients — paginated, searchable.
  Future<Paginated<StaffClient>> clients({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/clients',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, StaffClient.fromJson);
  }

  /// GET /documents — paginated documents of any type.
  Future<Paginated<StaffInvoiceRow>> documents({
    String type = 'invoice',
    String? status,
    String? search,
    String? clientId,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/documents',
      query: {
        'type': type,
        'status': status,
        'search': search,
        'client_id': clientId,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, StaffInvoiceRow.fromJson);
  }

  /// GET /payments-in — paginated payment records.
  Future<Paginated<StaffPayment>> payments({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/payments-in',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, StaffPayment.fromJson);
  }

  /// GET /tickets — staff queue (all clients).
  Future<List<StaffTicket>> tickets({String? status}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/tickets',
      query: {'status': status},
    );
    return Paginated.fromJson(body, StaffTicket.fromJson).items;
  }

  /// GET /tickets/{id} — full thread.
  Future<StaffTicket> ticket(String id) async {
    final body = await _api.get<Map<String, dynamic>>('/tickets/$id');
    final data = body['data'];
    return StaffTicket.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : body);
  }

  /// POST /tickets/{id}/reply — needs tickets.reply.
  Future<StaffTicket> replyTicket(String id, {required String message}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/tickets/$id/reply',
      body: {'message': message},
    );
    final data = body['data'];
    return StaffTicket.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : body);
  }

  /// POST /tickets/{id}/status — needs tickets.manage.
  Future<void> setTicketStatus(String id, String status) =>
      _api.post<dynamic>('/tickets/$id/status', body: {'status': status});
}

/// Permission names used by the staff app's navigation, verbatim from
/// routes/api.php middleware. Session.can() checks against these; super
/// admins hold '*'.
abstract final class Permissions {
  static const clientsRead = 'clients.read';
  static const documentsRead = 'documents.read';
  static const paymentsRead = 'payments_in.read';
  static const ticketsRead = 'tickets.read';
  static const ticketsReply = 'tickets.reply';
}

// Re-exported so staff screens rendering reply threads need one import.
typedef StaffTicketReply = TicketReply;

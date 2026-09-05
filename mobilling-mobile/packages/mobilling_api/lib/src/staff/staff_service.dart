import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api_client.dart';
import '../api_exception.dart';
import '../json.dart';
import '../paginated.dart';
import '../portal/support_models.dart' show TicketReply;
import 'admin_models.dart' show StaffUser;
import 'crm_models.dart' show SatisfactionCall;
import 'staff_models.dart';

/// Reports how many bytes of an upload have gone out. Structurally identical
/// to Dio's `ProgressCallback`, spelled as a plain function type so callers
/// need no Dio import to pass one.
typedef UploadProgress = void Function(int sent, int total);

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
    final body = await _api.get<dynamic>(
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
    final body = await _api.get<dynamic>(
      '/clients',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, StaffClient.fromJson);
  }

  // -------------------------------------------------------------------------
  // Clients — the record itself
  // -------------------------------------------------------------------------

  /// GET /clients/stats — the counters above the client list.
  Future<ClientCounters> clientStats() async {
    final body = await _api.get<dynamic>('/clients/stats');
    return ClientCounters.fromJson(_data(body));
  }

  /// GET /clients/{id}/profile — the whole 360 payload in one call.
  Future<ClientProfile> clientProfile(String clientId) async {
    final body = await _api.get<dynamic>('/clients/$clientId/profile');
    return ClientProfile.fromJson(_data(body));
  }

  /// POST /clients — needs `clients.create`.
  ///
  /// Email and phone are unique per tenant, so a duplicate comes back as a
  /// 422 whose message is already the sentence to show ("A client with this
  /// email already exists.").
  Future<StaffClient> createClient(ClientInput input) async {
    final body = await _api.post<dynamic>('/clients', body: input.toJson());
    return StaffClient.fromJson(_data(body));
  }

  /// PUT /clients/{id} — needs `clients.update`.
  ///
  /// The API writes the whole validated payload, so [input] must carry every
  /// field the record has, not only the changed ones. [ClientInput.from]
  /// exists for exactly that.
  Future<StaffClient> updateClient(String clientId, ClientInput input) async {
    final body = await _api.put<dynamic>(
      '/clients/$clientId',
      body: input.toJson(),
    );
    return StaffClient.fromJson(_data(body));
  }

  /// PUT /clients/{id}/notes — staff-only notes, never shown to the client.
  /// Capped at 10 000 characters; null clears them.
  Future<String?> updateClientNotes(String clientId, String? notes) async {
    final body = await _api.put<dynamic>(
      '/clients/$clientId/notes',
      body: {'notes': notes},
    );
    return _message(body);
  }

  /// POST /clients/{id}/make-reseller — needs `clients.update`.
  ///
  /// Raises a Reseller Membership subscription and its first invoice; the
  /// client only becomes a reseller once that invoice is paid. 422s when they
  /// already are one, or when the tenant has no such product.
  Future<String?> makeClientReseller(String clientId) async {
    final body = await _api.post<dynamic>('/clients/$clientId/make-reseller');
    return _message(body);
  }

  /// DELETE /clients/{id} — needs `clients.delete`.
  ///
  /// The server enforces no safety check of its own — no outstanding-balance
  /// guard, nothing — so a caller offering this must supply its own
  /// confirmation; there is no 422 to fall back on if someone taps it by
  /// mistake.
  Future<String?> deleteClient(String clientId) async {
    final body = await _api.delete<dynamic>('/clients/$clientId');
    return _message(body);
  }

  /// POST /clients/{id}/merge — needs `clients.delete`. [id] is "the first
  /// client" in the request but not necessarily the survivor: [keep] says
  /// which of the two the record continues as. Everything belonging to the
  /// other — documents, subscriptions, tickets, communications, and more —
  /// is reassigned to the survivor; [ClientMergeResult.moved] is the exact
  /// per-table count of what moved, meant for a confirmation summary before
  /// this runs, not just a report after.
  Future<ClientMergeResult> mergeClients(
    String clientId, {
    required String otherClientId,
    required String keep,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/clients/$clientId/merge',
      body: {'second_client_id': otherClientId, 'keep': keep},
    );
    return ClientMergeResult.fromJson(_data(body));
  }

  // -------------------------------------------------------------------------
  // Clients — additional contacts
  // -------------------------------------------------------------------------

  /// GET /clients/{id}/contacts — needs `clients.update` (the whole contact
  /// group sits behind that one permission, read included).
  Future<List<ClientContact>> clientContacts(String clientId) async {
    final body = await _api.get<dynamic>('/clients/$clientId/contacts');
    return Paginated.fromJson(body, ClientContact.fromJson).items;
  }

  /// POST /clients/{id}/contacts.
  Future<String?> createClientContact(
    String clientId, {
    required String name,
    String? email,
    String? phone,
    String? role,
    String? notes,
  }) async {
    final body = await _api.post<dynamic>(
      '/clients/$clientId/contacts',
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'notes': notes,
      },
    );
    return _message(body);
  }

  /// PUT /clients/{id}/contacts/{contact}.
  Future<String?> updateClientContact(
    String clientId,
    String contactId, {
    required String name,
    String? email,
    String? phone,
    String? role,
    String? notes,
  }) async {
    final body = await _api.put<dynamic>(
      '/clients/$clientId/contacts/$contactId',
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'notes': notes,
      },
    );
    return _message(body);
  }

  /// DELETE /clients/{id}/contacts/{contact}.
  Future<String?> deleteClientContact(String clientId, String contactId) async {
    final body = await _api.delete<dynamic>(
      '/clients/$clientId/contacts/$contactId',
    );
    return _message(body);
  }

  // -------------------------------------------------------------------------
  // Clients — communications, wallet, portal access
  // -------------------------------------------------------------------------

  /// GET /clients/{id}/communications — what the system actually sent them,
  /// with delivery status. [types] filters by log type (comma-joined
  /// server-side).
  Future<List<ClientCommunication>> clientCommunications(
    String clientId, {
    List<String> types = const [],
    int limit = 30,
  }) async {
    final body = await _api.get<dynamic>(
      '/clients/$clientId/communications',
      query: {'types': types.isEmpty ? null : types.join(','), 'limit': limit},
    );
    return Paginated.fromJson(body, ClientCommunication.fromJson).items;
  }

  /// GET /clients/{id}/credit — balance plus ledger. Needs `credit.manage`.
  Future<ClientCreditLedger> clientCredit(String clientId) async {
    final body = await _api.get<dynamic>('/clients/$clientId/credit');
    return ClientCreditLedger.fromJson(_data(body));
  }

  /// POST /clients/{id}/credit/adjust — needs `credit.manage`.
  ///
  /// [amount] is signed and must not be zero; a negative one removes credit
  /// and 422s if the wallet cannot cover it. [notes] is required — the ledger
  /// entry is the audit trail.
  Future<String?> adjustClientCredit(
    String clientId, {
    required double amount,
    required String notes,
  }) async {
    final body = await _api.post<dynamic>(
      '/clients/$clientId/credit/adjust',
      body: {'amount': amount, 'notes': notes},
    );
    return _message(body);
  }

  /// POST /documents/{id}/apply-credit — needs `credit.manage`.
  ///
  /// Spends as much of the client's wallet as the invoice's balance takes,
  /// recording it as a payment. 422s on anything that is not an invoice, and
  /// on an empty wallet.
  Future<String?> applyCreditToInvoice(String documentId) async {
    final body = await _api.post<dynamic>(
      '/documents/$documentId/apply-credit',
    );
    return _message(body);
  }

  /// POST /clients/{id}/portal-users — needs `clients.update`.
  ///
  /// The one portal-user verb the app was missing; update and delete live on
  /// [OpsService]. [role] is `admin` or `viewer`, and the password must be at
  /// least 8 characters. A duplicate email 422s.
  Future<String?> createClientPortalUser(
    String clientId, {
    required String name,
    required String email,
    required String password,
    required String role,
    String? phone,
  }) async {
    final body = await _api.post<dynamic>(
      '/clients/$clientId/portal-users',
      body: {
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        'phone': phone,
      },
    );
    return _message(body);
  }

  /// POST /clients/{id}/portal-login — needs `clients.portal_login`.
  ///
  /// Mints a live portal session for the client, creating a portal user
  /// first if they have none (which needs the client to have an email, or
  /// this 422s: "Client has no email address. Add an email first.").
  ///
  /// Returns the raw response rather than a parsed model: it already comes
  /// back shaped exactly like a login response (`user`, `token`,
  /// `user_type: 'client'`, `permissions`), so a caller builds
  /// `AuthSession.fromJson(body)` straight from it and hands that to
  /// `SessionController.impersonate` — the same swap-and-stash mechanism
  /// platform-admin tenant impersonation already uses (see
  /// `_adoptImpersonation` in `features/platform/tenants_screens.dart`).
  Future<Map<String, dynamic>> portalLoginAsClient(String clientId) =>
      _api.post<Map<String, dynamic>>('/clients/$clientId/portal-login');

  /// GET /satisfaction-calls/client/{id} — this client's call history, most
  /// recent first. Needs `menu.satisfaction_calls`, which most billing roles
  /// do not hold, so callers gate on it and drop the section otherwise.
  Future<List<SatisfactionCall>> clientSatisfactionCalls(
    String clientId,
  ) async {
    final body = await _api.get<dynamic>(
      '/satisfaction-calls/client/$clientId',
    );
    return Paginated.fromJson(body, SatisfactionCall.fromJson).items;
  }

  /// GET /documents — paginated documents of any type. [dateFrom]/[dateTo]
  /// filter on the document's own `date`, inclusive both ends.
  Future<Paginated<StaffInvoiceRow>> documents({
    String type = 'invoice',
    String? status,
    String? search,
    String? clientId,
    DateTime? dateFrom,
    DateTime? dateTo,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/documents',
      query: {
        'type': type,
        'status': status,
        'search': search,
        'client_id': clientId,
        'date_from': dateFrom == null ? null : _ymd(dateFrom),
        'date_to': dateTo == null ? null : _ymd(dateTo),
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
    final body = await _api.get<dynamic>(
      '/payments-in',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, StaffPayment.fromJson);
  }

  /// GET /tickets — staff queue (all clients).
  ///
  /// `TicketController::index` wraps the paginator one level deeper than
  /// most lists (`{data: {data: [...], current_page, ...}}`), so unwrap
  /// before parsing — handing the outer body to [Paginated] yields an empty
  /// queue regardless of data.
  Future<List<StaffTicket>> tickets({
    String? status,
    String? search,
    int perPage = 100,
  }) async {
    final body = await _api.get<dynamic>(
      '/tickets',
      query: {'status': status, 'search': search, 'per_page': perPage},
    );
    final inner = body is Map ? body['data'] : null;
    return Paginated.fromJson(
      inner is Map ? inner : body,
      StaffTicket.fromJson,
    ).items;
  }

  /// GET /tickets/{id} — full thread.
  Future<StaffTicket> ticket(String id) async {
    final body = await _api.get<Map<String, dynamic>>('/tickets/$id');
    final data = body['data'];
    return StaffTicket.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : body,
    );
  }

  /// GET /tickets/stats — the queue counters, flat (no `data` wrapper).
  Future<TicketStats> ticketStats() async {
    final body = await _api.get<dynamic>('/tickets/stats');
    return TicketStats.fromJson(
      body is Map ? Map<String, dynamic>.from(body) : const {},
    );
  }

  /// POST /tickets/{id}/reply — needs tickets.reply.
  ///
  /// [attachmentPaths] are local files posted as multipart under
  /// `attachments[]`; the backend caps them at 5 files of 5 MB each and
  /// accepts pdf/png/jpg/jpeg/txt/zip/doc/docx/xls/xlsx. With no files this
  /// stays a plain JSON post, exactly as the web client does.
  Future<StaffTicket> replyTicket(
    String id, {
    required String message,
    List<String> attachmentPaths = const [],
    UploadProgress? onProgress,
  }) async {
    final Map<String, dynamic> body;
    if (attachmentPaths.isEmpty) {
      body = await _api.post<Map<String, dynamic>>(
        '/tickets/$id/reply',
        body: {'message': message},
      );
    } else {
      final form = FormData.fromMap({'message': message});
      for (final path in attachmentPaths) {
        form.files.add(
          MapEntry('attachments[]', await MultipartFile.fromFile(path)),
        );
      }
      body = await _multipart('/tickets/$id/reply', form, onProgress);
    }
    final data = body['data'];
    return StaffTicket.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : body,
    );
  }

  /// POST /tickets/{id}/assign — needs tickets.manage. A null [userId]
  /// unassigns; the API rejects users outside the tenant or marked inactive.
  Future<StaffTicket> assignTicket(String id, {String? userId}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/tickets/$id/assign',
      body: {'user_id': userId},
    );
    final data = body['data'];
    return StaffTicket.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : body,
    );
  }

  /// GET /tickets/attachments/{id}/download — the raw bytes.
  ///
  /// Ticket files sit on the server's **private** disk, so unlike expense
  /// receipts they cannot be opened by URL: they have to be streamed with the
  /// bearer token attached.
  Future<Uint8List> ticketAttachment(String attachmentId) async {
    try {
      final response = await _api.raw.get<List<int>>(
        '/tickets/attachments/$attachmentId/download',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }

  /// GET /users — the staff accounts a ticket can be assigned to.
  ///
  /// There is no assignee-specific endpoint; the web dropdown reads `/users`
  /// too. Mind the permission: this route needs `settings.users`, which
  /// `tickets.manage` does **not** imply, so a ticket manager can be allowed
  /// to assign yet get a 403 populating the picker. Inactive accounts are
  /// dropped here because `assign` refuses them.
  Future<List<StaffUser>> assignableUsers() async {
    final body = await _api.get<dynamic>('/users', query: {'per_page': 200});
    return Paginated.fromJson(
      body,
      StaffUser.fromJson,
    ).items.where((user) => user.isActive).toList(growable: false);
  }

  /// POST /tickets/{id}/status — needs tickets.manage.
  Future<void> setTicketStatus(String id, String status) =>
      _api.post<dynamic>('/tickets/$id/status', body: {'status': status});

  /// Unwrap a `{data: {...}}` envelope, tolerating endpoints that answer with
  /// the object itself. `ClientResource` wraps; the hand-built profile and
  /// stats payloads wrap too, but `/tickets/stats` next door does not — so no
  /// caller may assume either shape.
  static Map<String, dynamic> _data(dynamic body) {
    if (body is! Map) return const {};
    final data = body['data'];
    return Map<String, dynamic>.from(
      data is Map ? data : Map<String, dynamic>.from(body),
    );
  }

  /// The API's own sentence for a write, when it sent one. Callers show it in
  /// a SnackBar rather than inventing wording that could contradict what the
  /// server actually did (a credit adjustment reports the new balance).
  static String? _message(dynamic body) =>
      body is Map ? body['message']?.toString() : null;

  /// Multipart POST through the shared client.
  ///
  /// [ApiClient] pins a JSON content type for every ordinary call, so uploads
  /// go through its documented `raw` escape hatch. The interceptors still run
  /// — bearer token, 401 handling, error shaping — only the body encoding
  /// differs, and failures are re-thrown as [ApiException] so no screen needs
  /// to import Dio.
  Future<Map<String, dynamic>> _multipart(
    String path,
    FormData form,
    UploadProgress? onProgress,
  ) async {
    try {
      final response = await _api.raw.post<Map<String, dynamic>>(
        path,
        data: form,
        onSendProgress: onProgress,
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }
}

/// GET /tickets/stats — the three counters the queue header shows.
///
/// Lives beside the service rather than in `staff_models.dart` to stay inside
/// this change's file ownership; move it there when convenient.
class TicketStats {
  const TicketStats({
    required this.awaitingReply,
    required this.answered,
    required this.closed,
  });

  /// Statuses `open` and `customer_reply` together — the work queue.
  final int awaitingReply;
  final int answered;
  final int closed;

  factory TicketStats.fromJson(Map<String, dynamic> json) => TicketStats(
    awaitingReply: json.count('awaiting_reply'),
    answered: json.count('answered'),
    closed: json.count('closed'),
  );
}

/// Permission names used by the staff app's navigation, verbatim from
/// routes/api.php middleware. Session.can() checks against these; super
/// admins hold '*'.
abstract final class Permissions {
  static const clientsRead = 'clients.read';
  static const clientsCreate = 'clients.create';

  /// Gates the client record *and* everything hanging off it that the API
  /// files under "managing the client": additional contacts, portal users,
  /// admin notes, and granting reseller status.
  static const clientsUpdate = 'clients.update';

  /// `POST /clients/{client}/portal-login`. Deliberately separate from
  /// [clientsUpdate]: signing in as someone is not the same right as editing
  /// their address.
  static const clientsPortalLogin = 'clients.portal_login';

  /// Delete and merge share this — both are irreversible and both take
  /// another record's data down with them.
  static const clientsDelete = 'clients.delete';

  /// The wallet: reading the balance and ledger, adjusting it, and spending
  /// it against an invoice all sit behind this one name.
  static const creditManage = 'credit.manage';

  /// Whether `/clients/stats` includes the money columns. The route itself
  /// only needs [clientsRead]; without this the value fields arrive absent.
  static const clientProfileSubscriptionValue =
      'client_profile.subscription_value';

  /// The other five client-detail figures the web profile page gates
  /// per-field. Unlike [clientProfileSubscriptionValue], the backend
  /// doesn't actually withhold this data for any of the five — the API
  /// returns it regardless — so these only control the mobile UI's own
  /// display, matching web's own (cosmetic, not authorization) behaviour.
  static const clientProfileTotalInvoiced = 'client_profile.total_invoiced';
  static const clientProfileTotalPaid = 'client_profile.total_paid';
  static const clientProfileBalanceDue = 'client_profile.balance_due';
  static const clientProfileActiveSubscriptions =
      'client_profile.active_subscriptions';
  static const clientProfileSubscriptionPrice =
      'client_profile.subscription_price';

  static const documentsRead = 'documents.read';
  static const paymentsRead = 'payments_in.read';
  static const ticketsRead = 'tickets.read';
  static const ticketsReply = 'tickets.reply';
  static const ticketsManage = 'tickets.manage';

  /// What `/users` sits behind. Separate from [ticketsManage] on purpose: it
  /// gates *reading the staff list*, so the assign picker needs it even
  /// though the assign call itself does not.
  static const settingsUsers = 'settings.users';
}

String _ymd(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

// Re-exported so staff screens rendering reply threads need one import.
typedef StaffTicketReply = TicketReply;

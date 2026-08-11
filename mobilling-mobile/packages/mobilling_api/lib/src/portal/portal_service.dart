import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api_client.dart';
import '../api_exception.dart';
import '../paginated.dart';
import 'account_models.dart';
import 'order_models.dart';
import 'portal_models.dart';
import 'services_models.dart';
import 'support_models.dart';

/// Typed access to the `/portal/*` endpoints (Milestone 2 slice: money).
///
/// Grows with the milestones — tickets, services and ordering join here later
/// rather than in separate services, because they all share the client scoping
/// and error behaviour of the portal route group.
class PortalService {
  const PortalService(this._api);

  final ApiClient _api;

  /// GET /portal/dashboard — the client-area home payload.
  Future<PortalDashboard> dashboard() async {
    final body = await _api.get<Map<String, dynamic>>('/portal/dashboard');
    return PortalDashboard.fromJson(body);
  }

  /// GET /portal/documents — paginated invoices (or quotations/proformas via
  /// [type]; the backend defaults to 'invoice' and hides draft/cancelled).
  Future<Paginated<InvoiceSummary>> documents({
    String type = 'invoice',
    String? status,
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/portal/documents',
      query: {
        'type': type,
        'status': status,
        'search': search,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, InvoiceSummary.fromJson);
  }

  /// GET /portal/documents/{id} — full invoice with items, payments and the
  /// invoiced_to / pay_to panels.
  Future<PortalDocument> document(String id) async {
    final body =
        await _api.get<Map<String, dynamic>>('/portal/documents/$id');
    final data = body['data'];
    return PortalDocument.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : body,
    );
  }

  /// POST /portal/documents/{id}/resend — email the document to the client.
  Future<void> resendDocument(String id) =>
      _api.post<dynamic>('/portal/documents/$id/resend');

  /// GET /portal/payments — paginated payment history.
  Future<Paginated<PaymentSummary>> payments({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/portal/payments',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, PaymentSummary.fromJson);
  }

  /// GET /portal/documents/{id}/pdf — the invoice as PDF bytes.
  ///
  /// The backend streams an authenticated download (no signed URLs), so the
  /// bytes come through the same bearer-token channel as everything else and
  /// the caller writes them to a file for the platform share sheet.
  Future<Uint8List> documentPdf(String id) =>
      _download('/portal/documents/$id/pdf');

  /// GET /portal/payments/{id}/receipt — a payment receipt as PDF bytes.
  Future<Uint8List> paymentReceipt(String paymentId) =>
      _download('/portal/payments/$paymentId/receipt');

  Future<Uint8List> _download(String path) async {
    try {
      final response = await _api.raw.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }

  /// POST /portal/documents/{id}/pay — start a Pesapal checkout.
  ///
  /// [amount] allows a partial payment; the backend clamps it to the balance
  /// due and rejects settled invoices or tenants without Pesapal configured
  /// (both arrive as a 400 whose message is safe to show verbatim).
  Future<CheckoutSession> payDocument(String id, {double? amount}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/documents/$id/pay',
      body: {'amount': ?amount},
    );
    return CheckoutSession.fromJson(body);
  }

  /// GET /portal/documents/{id}/pay/{paymentId}/status — poll a checkout.
  ///
  /// The IPN webhook settles the payment server-side, so polling works no
  /// matter what happens to the browser tab Pesapal was opened in.
  Future<InvoicePaymentStatus> paymentStatus(
    String documentId,
    String paymentId,
  ) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/portal/documents/$documentId/pay/$paymentId/status',
    );
    return InvoicePaymentStatus.fromJson(body);
  }

  /// GET /portal/statement — ledger of invoices vs payments with a running
  /// balance, optionally windowed by date (Y-m-d).
  Future<Statement> statement({String? startDate, String? endDate}) async {
    final body = await _api.get<dynamic>(
      '/portal/statement',
      query: {'start_date': startDate, 'end_date': endDate},
    );
    return Statement.fromJson(body);
  }

  // -------------------------------------------------------------------------
  // Support
  // -------------------------------------------------------------------------

  /// GET /portal/tickets — all of the client's tickets, open first.
  Future<List<PortalTicket>> tickets() async {
    final body = await _api.get<dynamic>('/portal/tickets');
    return Paginated.fromJson(body, PortalTicket.fromJson).items;
  }

  /// GET /portal/tickets/{id} — a ticket with its full reply thread.
  Future<PortalTicket> ticket(String id) async {
    final body = await _api.get<Map<String, dynamic>>('/portal/tickets/$id');
    return PortalTicket.fromJson(_unwrap(body));
  }

  /// POST /portal/tickets — open a ticket. [attachmentPaths] are local files
  /// sent as multipart (backend limit: 5 files, 5 MB each).
  Future<PortalTicket> createTicket({
    required String subject,
    required String message,
    String priority = 'medium',
    String department = 'support',
    String? relatedService,
    List<String> attachmentPaths = const [],
  }) async {
    final body = await _postWithAttachments('/portal/tickets', {
      'subject': subject,
      'message': message,
      'priority': priority,
      'department': department,
      'related_service': ?relatedService,
    }, attachmentPaths);
    return PortalTicket.fromJson(_unwrap(body));
  }

  /// POST /portal/tickets/{id}/reply — returns the refreshed thread.
  Future<PortalTicket> replyTicket(
    String id, {
    required String message,
    List<String> attachmentPaths = const [],
  }) async {
    final body = await _postWithAttachments(
      '/portal/tickets/$id/reply',
      {'message': message},
      attachmentPaths,
    );
    return PortalTicket.fromJson(_unwrap(body));
  }

  /// POST /portal/tickets/{id}/close.
  Future<void> closeTicket(String id) =>
      _api.post<dynamic>('/portal/tickets/$id/close');

  /// GET /portal/tickets/attachments/{id}/download — attachment bytes.
  Future<Uint8List> ticketAttachment(String attachmentId) =>
      _download('/portal/tickets/attachments/$attachmentId/download');

  /// GET /portal/announcements — the tenant's published announcements.
  Future<List<Announcement>> announcements() async {
    final body =
        await _api.get<dynamic>('/portal/announcements');
    return Paginated.fromJson(body, Announcement.fromJson).items;
  }

  /// GET /portal/knowledgebase — categories with published articles,
  /// optionally filtered by [search] (matching categories only).
  Future<List<KbCategory>> knowledgebase({String? search}) async {
    final body = await _api.get<dynamic>(
      '/portal/knowledgebase',
      query: {'search': search},
    );
    return Paginated.fromJson(body, KbCategory.fromJson).items;
  }

  /// GET /portal/knowledgebase/{slug} — a full article (increments views).
  Future<KbArticle> kbArticle(String slug) async {
    final body =
        await _api.get<dynamic>('/portal/knowledgebase/$slug');
    return KbArticle.fromJson(_unwrap(body));
  }

  // -------------------------------------------------------------------------
  // Services: subscriptions, hosting, domains
  // -------------------------------------------------------------------------

  /// GET /portal/subscriptions — everything except cancelled ones.
  Future<List<ClientSubscription>> subscriptions() async {
    final body =
        await _api.get<dynamic>('/portal/subscriptions');
    return Paginated.fromJson(body, ClientSubscription.fromJson).items;
  }

  /// POST /portal/subscriptions/{id}/generate-invoice — bill now.
  Future<CreatedInvoiceRef> generateSubscriptionInvoice(String id) async {
    final body = await _api.post<Map<String, dynamic>>(
        '/portal/subscriptions/$id/generate-invoice');
    return CreatedInvoiceRef.fromJson(body);
  }

  /// GET /portal/hosting.
  Future<List<HostingAccount>> hostingAccounts() async {
    final body = await _api.get<dynamic>('/portal/hosting');
    return Paginated.fromJson(body, HostingAccount.fromJson).items;
  }

  /// GET /portal/hosting/{id}.
  Future<HostingDetail> hostingAccount(String id) async {
    final body = await _api.get<Map<String, dynamic>>('/portal/hosting/$id');
    return HostingDetail.fromJson(_unwrap(body));
  }

  /// POST /portal/hosting/{id}/sso — a one-time cPanel/webmail login URL.
  /// [goto] deep-links inside cPanel (values from HostingDetail.shortcuts).
  Future<String> hostingSsoUrl(String id,
      {String service = 'cpanel', String? goto}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/hosting/$id/sso',
      body: {'service': service, 'goto': ?goto},
    );
    return body['url']?.toString() ?? '';
  }

  /// POST /portal/hosting/{id}/refresh-usage — re-read disk usage from cPanel.
  Future<void> refreshHostingUsage(String id) =>
      _api.post<dynamic>('/portal/hosting/$id/refresh-usage');

  /// POST /portal/hosting/{id}/change-password.
  Future<void> changeHostingPassword(String id, String password) =>
      _api.post<dynamic>('/portal/hosting/$id/change-password',
          body: {'password': password, 'password_confirmation': password});

  /// POST /portal/hosting/{id}/request-cancellation — opens a staff ticket.
  Future<String?> requestHostingCancellation(
    String id, {
    required String reason,
    required String when, // immediate | end_of_period
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/hosting/$id/request-cancellation',
      body: {'reason': reason, 'when': when},
    );
    return body['message']?.toString();
  }

  /// GET /portal/hosting/{id}/upgrade-options.
  Future<HostingUpgradeOptions> hostingUpgradeOptions(String id) async {
    final body = await _api
        .get<Map<String, dynamic>>('/portal/hosting/$id/upgrade-options');
    return HostingUpgradeOptions.fromJson(_unwrap(body));
  }

  /// POST /portal/hosting/{id}/upgrade — downgrades apply immediately;
  /// upgrades create a prorated invoice (returned) and apply once paid.
  Future<CreatedInvoiceRef?> upgradeHosting(String id, String planId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/hosting/$id/upgrade',
      body: {'product_service_id': planId},
    );
    return body['data'] is Map ? CreatedInvoiceRef.fromJson(body) : null;
  }

  /// GET /portal/domains — the client's domains plus status counts.
  Future<DomainList> domains() async {
    final body = await _api.get<Map<String, dynamic>>('/portal/domains');
    return DomainList.fromJson(body);
  }

  /// GET /portal/domains/{id}.
  Future<DomainDetail> domain(String id) async {
    final body = await _api.get<Map<String, dynamic>>('/portal/domains/$id');
    return DomainDetail.fromJson(_unwrap(body));
  }

  /// POST /portal/domains/{id}/renew — creates a renewal invoice.
  Future<CreatedInvoiceRef> renewDomain(String id, {int years = 1}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/domains/$id/renew',
      body: {'years': years},
    );
    return CreatedInvoiceRef.fromJson(body);
  }

  /// POST /portal/domains/{id}/epp-code — the transfer auth code.
  Future<String> domainEppCode(String id) async {
    final body =
        await _api.post<Map<String, dynamic>>('/portal/domains/$id/epp-code');
    return body['auth_info']?.toString() ?? '';
  }

  /// GET /portal/domains/{id}/nameservers.
  Future<DomainNameservers> domainNameservers(String id) async {
    final body = await _api
        .get<Map<String, dynamic>>('/portal/domains/$id/nameservers');
    return DomainNameservers.fromJson(_unwrap(body));
  }

  /// PUT /portal/domains/{id}/nameservers.
  Future<void> updateDomainNameservers(String id, List<String> nameservers) =>
      _api.put<dynamic>('/portal/domains/$id/nameservers',
          body: {'nameservers': nameservers});

  /// PUT /portal/domains/{id}/auto-renew — portal admins only (403 otherwise).
  Future<void> setDomainAutoRenew(String id, bool enabled) =>
      _api.put<dynamic>('/portal/domains/$id/auto-renew',
          body: {'enabled': enabled});

  // -------------------------------------------------------------------------
  // Account: profile, portal users, credit
  // -------------------------------------------------------------------------

  /// GET /portal/profile — the signed-in user plus their company record.
  Future<PortalProfile> profile() async {
    final body = await _api.get<Map<String, dynamic>>('/portal/profile');
    return PortalProfile.fromJson(body);
  }

  /// PUT /portal/profile — name and phone are the only self-editable fields.
  Future<void> updateProfile({String? name, String? phone}) =>
      _api.put<dynamic>('/portal/profile',
          body: {'name': ?name, 'phone': ?phone});

  /// POST /portal/profile/change-password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _api.post<dynamic>('/portal/profile/change-password', body: {
        'current_password': currentPassword,
        'password': newPassword,
        'password_confirmation': newPassword,
      });

  /// GET /portal/users — portal admins only (403 otherwise).
  Future<List<PortalUser>> portalUsers() async {
    final body = await _api.get<dynamic>('/portal/users');
    return Paginated.fromJson(body, PortalUser.fromJson).items;
  }

  /// POST /portal/users — add a portal login for a colleague.
  Future<PortalUser> createPortalUser({
    required String name,
    required String email,
    required String password,
    required String role, // admin | viewer
    String? phone,
  }) async {
    final body = await _api.post<Map<String, dynamic>>('/portal/users', body: {
      'name': name,
      'email': email,
      'password': password,
      'role': role,
      'phone': ?phone,
    });
    return PortalUser.fromJson(_unwrap(body));
  }

  /// PUT /portal/users/{id}.
  Future<void> updatePortalUser(
    String id, {
    String? name,
    String? phone,
    String? role,
    bool? isActive,
  }) =>
      _api.put<dynamic>('/portal/users/$id', body: {
        'name': ?name,
        'phone': ?phone,
        'role': ?role,
        'is_active': ?isActive,
      });

  /// DELETE /portal/users/{id} — cannot delete yourself (422).
  Future<void> deletePortalUser(String id) =>
      _api.delete<dynamic>('/portal/users/$id');

  /// GET /portal/credit — wallet balance and recent ledger.
  Future<CreditWallet> credit() async {
    final body = await _api.get<Map<String, dynamic>>('/portal/credit');
    return CreditWallet.fromJson(_unwrap(body));
  }

  /// POST /portal/credit/topup — invoice now, credit lands when it's paid.
  Future<CreatedInvoiceRef> topupCredit(double amount) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/credit/topup',
      body: {'amount': amount},
    );
    return CreatedInvoiceRef.fromJson(body);
  }

  /// POST /portal/documents/{id}/apply-credit — settle an invoice (fully or
  /// partly) from the wallet.
  Future<String?> applyCreditToInvoice(String documentId) async {
    final body = await _api
        .post<Map<String, dynamic>>('/portal/documents/$documentId/apply-credit');
    return body['message']?.toString();
  }

  // -------------------------------------------------------------------------
  // Push notifications
  // -------------------------------------------------------------------------

  /// POST /portal/device-tokens — register this device's FCM token. Repeat
  /// calls (token refresh, re-login) upsert; a token registered by a previous
  /// account on the same phone moves to the current one.
  Future<void> registerDeviceToken(String token, {String? platform}) =>
      _api.post<dynamic>('/portal/device-tokens',
          body: {'token': token, 'platform': ?platform});

  /// DELETE /portal/device-tokens — call on sign-out so the next owner of
  /// this account doesn't keep receiving pushes on this phone.
  Future<void> unregisterDeviceToken(String token) =>
      _api.delete<dynamic>('/portal/device-tokens', body: {'token': token});

  // -------------------------------------------------------------------------
  // Ordering
  // -------------------------------------------------------------------------

  /// GET /portal/catalog — grouped, portal-visible products.
  Future<List<CatalogGroup>> catalog() async {
    final body = await _api.get<dynamic>('/portal/catalog');
    return Paginated.fromJson(body, CatalogGroup.fromJson).items;
  }

  /// GET /portal/domain-tlds — offered TLDs with pricing.
  Future<List<TldPricing>> tlds() async {
    final body = await _api.get<dynamic>('/portal/domain-tlds');
    return Paginated.fromJson(body, TldPricing.fromJson).items;
  }

  /// GET /portal/domain-addons — addons offered with a bundled domain.
  Future<List<DomainAddon>> domainAddons() async {
    final body =
        await _api.get<dynamic>('/portal/domain-addons');
    return Paginated.fromJson(body, DomainAddon.fromJson).items;
  }

  /// GET /portal/products/{id}/addons.
  Future<List<ProductAddon>> productAddons(String productId) async {
    final body = await _api
        .get<Map<String, dynamic>>('/portal/products/$productId/addons');
    return Paginated.fromJson(body, ProductAddon.fromJson).items;
  }

  /// GET /portal/products/{id}/config-options.
  Future<List<ConfigOptionGroup>> configOptions(String productId) async {
    final body = await _api.get<dynamic>(
        '/portal/products/$productId/config-options');
    return Paginated.fromJson(body, ConfigOptionGroup.fromJson).items;
  }

  /// POST /portal/coupons/validate — server-computed discount preview.
  Future<CouponResult> validateCoupon({
    required String code,
    required String productId,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/coupons/validate',
      body: {'code': code, 'product_service_id': productId},
    );
    return CouponResult.fromJson(body);
  }

  /// GET /portal/domains/check — registry availability + pricing.
  Future<DomainCheckResult> checkDomain(String name) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/portal/domains/check',
      query: {'name': name.toLowerCase().trim()},
    );
    return DomainCheckResult.fromJson(body);
  }

  /// POST /portal/orders — place an order; pays via the returned invoice.
  ///
  /// For hosting products [label] carries the domain; [domainMode] selects
  /// register / transfer / existing, with [authInfo] required for transfers.
  Future<PlacedOrder> placeOrder({
    required String productId,
    String? label,
    String? domainMode,
    String? authInfo,
    int? years,
    List<String> domainAddonIds = const [],
    List<String> productAddonIds = const [],
    List<ConfigSelection> configOptions = const [],
    String? couponCode,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/orders',
      body: {
        'product_service_id': productId,
        'label': ?label,
        'domain_mode': ?domainMode,
        'auth_info': ?authInfo,
        'years': ?years,
        if (domainAddonIds.isNotEmpty) 'addons': domainAddonIds,
        if (productAddonIds.isNotEmpty) 'product_addon_ids': productAddonIds,
        if (configOptions.isNotEmpty)
          'config_options': configOptions.map((c) => c.toJson()).toList(),
        'coupon_code': ?couponCode,
      },
    );
    return PlacedOrder.fromJson(body);
  }

  /// POST /portal/domains/order — standalone domain register/transfer;
  /// creates the invoice to pay.
  Future<PlacedOrder> orderDomain({
    required String name,
    required int years,
    required String action, // register | transfer
    String? authInfo,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/portal/domains/order',
      body: {
        'name': name.toLowerCase().trim(),
        'years': years,
        'action': action,
        'auth_info': ?authInfo,
      },
    );
    return PlacedOrder.fromJson(body);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Most single-object endpoints wrap in `{data: {...}}`; a few don't.
  Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  /// JSON post when there are no files; multipart otherwise. Laravel reads
  /// `attachments[]` as the array the validator expects.
  Future<Map<String, dynamic>> _postWithAttachments(
    String path,
    Map<String, dynamic> fields,
    List<String> attachmentPaths,
  ) async {
    if (attachmentPaths.isEmpty) {
      return _api.post<Map<String, dynamic>>(path, body: fields);
    }

    final form = FormData.fromMap(fields);
    for (final filePath in attachmentPaths) {
      form.files.add(MapEntry(
        'attachments[]',
        await MultipartFile.fromFile(filePath),
      ));
    }

    try {
      final response = await _api.raw.post<Map<String, dynamic>>(
        path,
        data: form,
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }
}

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api_client.dart';
import '../api_exception.dart';
import '../json.dart';
import '../paginated.dart';
import 'comms_models.dart';

/// Typed access to the staff communications endpoints: SMS credits, client
/// broadcasts, the WhatsApp marketing pipeline and the social-media planner.
///
/// Grouped into one service because the mobile app presents them as one area,
/// and because they share no state with the billing endpoints in
/// [StaffService]. Permission gating differs per route — see [CommsPermissions]
/// — so screens should hide actions they cannot perform rather than surface a
/// 403 after the fact.
class CommsService {
  const CommsService(this._api);

  final ApiClient _api;

  // ─── SMS ──────────────────────────────────────────────────────────────────

  /// GET /sms/packages — the active credit tiers, cheapest first.
  Future<List<SmsPackageOption>> smsPackages() async {
    final body = await _api.get<dynamic>('/sms/packages');
    return Paginated.fromJson(body, SmsPackageOption.fromJson).items;
  }

  /// GET /sms/balance — live reseller balance.
  ///
  /// Always 200: an unconfigured tenant or a failed upstream call comes back as
  /// a null balance with an explanation, which [SmsBalance] carries rather than
  /// throwing.
  Future<SmsBalance> smsBalance() async {
    final body = await _api.get<Map<String, dynamic>>('/sms/balance');
    return SmsBalance.fromJson(_data(body));
  }

  /// POST /sms/checkout — needs menu.sms. Creates the purchase and returns the
  /// Pesapal payment URL for the caller to open.
  ///
  /// [quantity] must be at least 100 and must fall inside a configured package,
  /// or the server answers 422.
  Future<SmsCheckout> smsCheckout({required int quantity}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/sms/checkout',
      body: {'sms_quantity': quantity},
    );
    return SmsCheckout.fromJson(_data(body));
  }

  /// GET /sms/purchases — paginated history, newest first.
  Future<Paginated<SmsPurchase>> smsPurchases({int page = 1}) async {
    final body = await _api.get<dynamic>(
      '/sms/purchases',
      query: {'page': page},
    );
    return Paginated.fromJson(body, SmsPurchase.fromJson);
  }

  /// GET /sms/purchases/{id}/status — re-polls Pesapal for pending purchases
  /// before answering, so this is the way to confirm a payment landed.
  Future<SmsPurchaseStatus> smsPurchaseStatus(String purchaseId) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/sms/purchases/$purchaseId/status',
    );
    return SmsPurchaseStatus.fromJson(_data(body));
  }

  /// POST /sms/purchases/{id}/retry — needs menu.sms. Returns the payment URL
  /// to reopen, either the stored one or a freshly submitted order.
  Future<String?> retrySmsPurchase(String purchaseId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/sms/purchases/$purchaseId/retry',
    );
    return _data(body)['redirect_url']?.toString();
  }

  /// POST /sms/request-activation — needs menu.sms. Notifies the super admins;
  /// 422 when SMS is already configured. Returns the server's message.
  Future<String> requestSmsActivation() async {
    final body = await _api.post<Map<String, dynamic>>(
      '/sms/request-activation',
    );
    return body['message']?.toString() ?? 'Request sent.';
  }

  /// GET /sms/purchases/{id}/receipt — a PDF, only once the purchase has
  /// completed (422 otherwise).
  Future<Uint8List> smsReceiptPdf(String purchaseId) =>
      _download('/sms/purchases/$purchaseId/receipt');

  /// GET /sms/purchases/{id}/invoice — a PDF, available at any status.
  Future<Uint8List> smsInvoicePdf(String purchaseId) =>
      _download('/sms/purchases/$purchaseId/invoice');

  // ─── Broadcasts ───────────────────────────────────────────────────────────

  /// GET /broadcasts — needs menu.broadcast. Paginated, newest first.
  Future<Paginated<Broadcast>> broadcasts({
    int page = 1,
    int perPage = 15,
  }) async {
    final body = await _api.get<dynamic>(
      '/broadcasts',
      query: {'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, Broadcast.fromJson);
  }

  /// POST /broadcasts — needs menu.broadcast.
  ///
  /// The send always runs in the background (`SendBroadcastJob`), so the 202
  /// response carries only [BroadcastSendResult.totalRecipients], never a
  /// delivery tally — poll [broadcasts] and watch `in_progress` for that.
  ///
  /// [subject] and [body] are required for email and both; [smsBody] for sms
  /// and both, capped at 160 characters; [whatsappBody] for whatsapp alone.
  /// Omitting [clientIds] sends to **every** client with a usable address on
  /// the chosen channel — callers should confirm that with the user first.
  Future<BroadcastSendResult> sendBroadcast({
    required BroadcastChannel channel,
    String? subject,
    String? body,
    String? smsBody,
    String? whatsappBody,
    List<String>? clientIds,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/broadcasts',
      body: {
        'channel': channel.value,
        // Only send the fields the chosen channel validates, so an unused
        // leftover draft in the form cannot fail validation.
        if (channel.includesEmail) 'subject': subject,
        if (channel.includesEmail) 'body': body,
        if (channel.includesSms) 'sms_body': smsBody,
        if (channel.includesWhatsapp) 'whatsapp_body': whatsappBody,
        if (clientIds != null && clientIds.isNotEmpty) 'client_ids': clientIds,
      },
    );
    return BroadcastSendResult.fromJson(response);
  }

  /// GET /broadcasts/{id}/recipients?status= — who did or didn't get it.
  Future<List<BroadcastRecipient>> broadcastRecipients(
    String broadcastId, {
    required bool sent,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/broadcasts/$broadcastId/recipients',
      query: {'status': sent ? 'sent' : 'failed'},
    );
    return Paginated.fromJson(_data(body), BroadcastRecipient.fromJson).items;
  }

  /// POST /broadcasts/{id}/resend-failed — a fresh broadcast to only last
  /// time's failures. 422s with no recipients if there weren't any.
  Future<BroadcastSendResult> resendFailedBroadcast(String broadcastId) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/broadcasts/$broadcastId/resend-failed',
    );
    return BroadcastSendResult.fromJson(response);
  }

  // ─── WhatsApp pipeline ────────────────────────────────────────────────────

  /// GET /whatsapp-contacts — needs whatsapp_contacts.read.
  ///
  /// Unpaginated (the controller returns `->get()`), and already scoped
  /// server-side: without whatsapp_contacts.view_all a user sees only the
  /// contacts they registered plus unowned ones.
  Future<List<WhatsappContact>> whatsappContacts({
    String? search,
    String? label,
    String? source,
  }) async {
    final body = await _api.get<List<dynamic>>(
      '/whatsapp-contacts',
      query: {'search': search, 'label': label, 'source': source},
    );
    return Paginated.fromJson(body, WhatsappContact.fromJson).items;
  }

  /// GET /whatsapp-contacts/stats — needs whatsapp_contacts.read.
  Future<WhatsappContactStats> whatsappContactStats() async {
    final body = await _api.get<Map<String, dynamic>>(
      '/whatsapp-contacts/stats',
    );
    return WhatsappContactStats.fromJson(body);
  }

  /// POST /whatsapp-contacts — needs whatsapp_contacts.create.
  ///
  /// [phone] is unique per tenant, so a repeat number is a 422 rather than a
  /// second row. The response also reports any **client** already holding that
  /// number — see [WhatsappContactCreated.matchesExistingClient].
  Future<WhatsappContactCreated> createWhatsappContact({
    required String name,
    required String phone,
    required WhatsappLabel label,
    required WhatsappSource source,
    bool isImportant = false,
    String? campaignId,
    String? notes,
    List<String>? services,
    DateTime? nextFollowupDate,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/whatsapp-contacts',
      body: {
        'name': name,
        'phone': phone,
        'label': label.value,
        'source': source.value,
        'is_important': isImportant,
        'campaign_id': ?campaignId,
        'notes': ?notes,
        if (services != null && services.isNotEmpty) 'services': services,
        if (nextFollowupDate != null)
          'next_followup_date': _day(nextFollowupDate),
      },
    );
    return WhatsappContactCreated.fromJson(body);
  }

  /// PUT /whatsapp-contacts/{id} — needs whatsapp_contacts.update.
  ///
  /// Every field is `sometimes`; pass only what changed. Without
  /// whatsapp_contacts.view_all the server refuses contacts someone else
  /// registered (403).
  Future<WhatsappContact> updateWhatsappContact(
    String contactId, {
    String? name,
    String? phone,
    WhatsappLabel? label,
    WhatsappSource? source,
    bool? isImportant,
    String? campaignId,
    String? notes,
    List<String>? services,
    DateTime? nextFollowupDate,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/whatsapp-contacts/$contactId',
      body: {
        'name': ?name,
        'phone': ?phone,
        'label': ?label?.value,
        'source': ?source?.value,
        'is_important': ?isImportant,
        'campaign_id': ?campaignId,
        'notes': ?notes,
        'services': ?services,
        if (nextFollowupDate != null)
          'next_followup_date': _day(nextFollowupDate),
      },
    );
    return WhatsappContact.fromJson(body);
  }

  /// DELETE /whatsapp-contacts/{id} — needs whatsapp_contacts.delete. Takes
  /// the contact's logged calls with it.
  Future<void> deleteWhatsappContact(String contactId) =>
      _api.delete<dynamic>('/whatsapp-contacts/$contactId');

  /// POST /whatsapp-contacts/{id}/convert — needs whatsapp_contacts.convert.
  ///
  /// Either link an existing client with [clientId] or create one, in which
  /// case [clientName] is required and the contact's own number is used when
  /// [clientPhone] is omitted — unless a client already holds it, in which
  /// case the server saves the new client without a phone rather than fail.
  /// The contact comes back linked and moved to the `new_customer` stage.
  Future<WhatsappContact> convertWhatsappContact(
    String contactId, {
    String? clientId,
    String? clientName,
    String? clientEmail,
    String? clientPhone,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/whatsapp-contacts/$contactId/convert',
      body: {
        'client_id': ?clientId,
        'client_name': ?clientName,
        'client_email': ?clientEmail,
        'client_phone': ?clientPhone,
      },
    );
    return WhatsappContact.fromJson(body);
  }

  /// POST /whatsapp-contacts/{id}/claim — needs whatsapp_contacts.update.
  /// Takes ownership of an unowned contact; 403 if someone else owns it.
  Future<WhatsappContact> claimWhatsappContact(String contactId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/whatsapp-contacts/$contactId/claim',
    );
    return WhatsappContact.fromJson(body);
  }

  /// POST /whatsapp-contacts/{id}/unclaim — needs whatsapp_contacts.update.
  /// Releases the contact back to the shared pool. Own contacts only, unless
  /// the caller holds whatsapp_contacts.view_all.
  Future<WhatsappContact> unclaimWhatsappContact(String contactId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/whatsapp-contacts/$contactId/unclaim',
    );
    return WhatsappContact.fromJson(body);
  }

  /// POST /whatsapp-contacts/{id}/assign — needs whatsapp_contacts.view_all.
  /// Hands ownership to [userId], who then sees it as one of theirs.
  Future<WhatsappContact> assignWhatsappContact(
    String contactId, {
    required String userId,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/whatsapp-contacts/$contactId/assign',
      body: {'user_id': userId},
    );
    return WhatsappContact.fromJson(body);
  }

  /// POST /whatsapp-contacts/claim-bulk — needs whatsapp_contacts.view_all.
  ///
  /// Claims the unowned contacts among [ids]; omitting them claims every
  /// unowned contact in the tenant. Contacts someone else owns are never
  /// taken. Returns how many moved.
  Future<int> claimWhatsappContactsBulk({List<String>? ids}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/whatsapp-contacts/claim-bulk',
      body: {if (ids != null && ids.isNotEmpty) 'ids': ids},
    );
    return readInt(body['claimed']);
  }

  /// GET /whatsapp-campaigns — needs whatsapp_campaigns.read. Unpaginated,
  /// with lead and conversion counts attached.
  Future<List<WhatsappCampaign>> whatsappCampaigns() async {
    final body = await _api.get<List<dynamic>>('/whatsapp-campaigns');
    return Paginated.fromJson(body, WhatsappCampaign.fromJson).items;
  }

  /// POST /whatsapp-campaigns — needs whatsapp_campaigns.create.
  Future<WhatsappCampaign> createWhatsappCampaign({
    required String name,
    required DateTime startDate,
    required double budget,
    DateTime? endDate,
    String? notes,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/whatsapp-campaigns',
      body: {
        'name': name,
        'start_date': _day(startDate),
        'budget': budget,
        if (endDate != null) 'end_date': _day(endDate),
        'notes': ?notes,
      },
    );
    return WhatsappCampaign.fromJson(_data(body));
  }

  /// PUT /whatsapp-campaigns/{id} — needs whatsapp_campaigns.update.
  Future<WhatsappCampaign> updateWhatsappCampaign(
    String campaignId, {
    String? name,
    DateTime? startDate,
    double? budget,
    DateTime? endDate,
    String? notes,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/whatsapp-campaigns/$campaignId',
      body: {
        'name': ?name,
        if (startDate != null) 'start_date': _day(startDate),
        'budget': ?budget,
        if (endDate != null) 'end_date': _day(endDate),
        'notes': ?notes,
      },
    );
    return WhatsappCampaign.fromJson(_data(body));
  }

  /// DELETE /whatsapp-campaigns/{id} — needs whatsapp_campaigns.delete. The
  /// leads it produced survive; only the campaign row goes.
  Future<void> deleteWhatsappCampaign(String campaignId) =>
      _api.delete<dynamic>('/whatsapp-campaigns/$campaignId');

  /// GET /whatsapp-contacts/{id}/followups — needs whatsapp_contacts.log.
  /// Newest call first (the relation orders by call_date desc).
  Future<List<WhatsappFollowup>> whatsappFollowups(String contactId) async {
    final body = await _api.get<List<dynamic>>(
      '/whatsapp-contacts/$contactId/followups',
    );
    return Paginated.fromJson(body, WhatsappFollowup.fromJson).items;
  }

  /// POST /whatsapp-contacts/{id}/followups — needs whatsapp_contacts.log.
  ///
  /// Passing [nextFollowupDate] also moves the contact's own
  /// `next_followup_date`, which is what drives the due list.
  Future<WhatsappFollowup> logWhatsappFollowup(
    String contactId, {
    required DateTime callDate,
    required FollowupOutcome outcome,
    String? notes,
    DateTime? nextFollowupDate,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/whatsapp-contacts/$contactId/followups',
      body: {
        'call_date': _day(callDate),
        'outcome': outcome.value,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (nextFollowupDate != null)
          'next_followup_date': _day(nextFollowupDate),
      },
    );
    return WhatsappFollowup.fromJson(body);
  }

  /// DELETE /whatsapp-contacts/{id}/followups/{followup} — needs
  /// whatsapp_contacts.log. Removes a mis-logged call; the contact's own
  /// `next_followup_date` is left as it stands.
  Future<void> deleteWhatsappFollowup(String contactId, String followupId) =>
      _api.delete<dynamic>(
        '/whatsapp-contacts/$contactId/followups/$followupId',
      );

  // ─── Social media planner ─────────────────────────────────────────────────

  /// GET /social/platforms — needs social.read. The tenant's configured
  /// platforms, in display order.
  Future<List<SocialPlatformConfig>> socialPlatforms() async {
    final body = await _api.get<dynamic>('/social/platforms');
    return Paginated.fromJson(body, SocialPlatformConfig.fromJson).items;
  }

  /// POST /social/platforms — needs social.targets. [name] becomes the
  /// posting-row key (`platform`) — an existing post's rows don't retroactively
  /// gain one, so add platforms before they're needed, not after.
  Future<SocialPlatformConfig> createSocialPlatform({
    required String name,
    required String label,
    String? color,
    String? icon,
    String? profileUrl,
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/social/platforms',
      body: {
        'name': name,
        'label': label,
        'color': ?color,
        'icon': ?icon,
        'profile_url': ?profileUrl,
        'is_active': isActive,
        'sort_order': sortOrder,
      },
    );
    return SocialPlatformConfig.fromJson(_data(body));
  }

  /// PUT /social/platforms/{id} — needs social.targets. `name` is immutable
  /// once created (it's the posting-row key), so it isn't a parameter here.
  Future<SocialPlatformConfig> updateSocialPlatform(
    String id, {
    String? label,
    String? color,
    String? icon,
    String? profileUrl,
    bool? isActive,
    int? sortOrder,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/social/platforms/$id',
      body: {
        'label': ?label,
        'color': ?color,
        'icon': ?icon,
        'profile_url': ?profileUrl,
        'is_active': ?isActive,
        'sort_order': ?sortOrder,
      },
    );
    return SocialPlatformConfig.fromJson(_data(body));
  }

  /// DELETE /social/platforms/{id} — needs social.targets.
  Future<void> deleteSocialPlatform(String id) =>
      _api.delete<dynamic>('/social/platforms/$id');

  /// GET /social/posts — needs social.read. Unpaginated, ordered by schedule.
  ///
  /// [weekStart] narrows to that Monday's seven days; omit for everything.
  Future<List<SocialPost>> socialPosts({
    DateTime? weekStart,
    String? status,
    String? type,
  }) async {
    final body = await _api.get<dynamic>(
      '/social/posts',
      query: {
        'week_start': weekStart == null ? null : _day(weekStart),
        'status': status,
        'type': type,
      },
    );
    return Paginated.fromJson(body, SocialPost.fromJson).items;
  }

  /// GET /social/targets — needs social.read. Null when no target is set yet.
  Future<SocialTarget?> socialTarget() async {
    final body = await _api.get<Map<String, dynamic>>('/social/targets');
    final data = body['data'];
    if (data is! Map || data.isEmpty) return null;
    return SocialTarget.fromJson(Map<String, dynamic>.from(data));
  }

  /// GET /social/weekly-summary — needs social.read. Target vs actual for the
  /// week containing [weekStart] (defaults server-side to the current week).
  Future<SocialWeeklySummary> socialWeeklySummary({DateTime? weekStart}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/social/weekly-summary',
      query: {'week_start': weekStart == null ? null : _day(weekStart)},
    );
    return SocialWeeklySummary.fromJson(body);
  }

  /// POST /social/posts — needs social.create.
  ///
  /// Creating a post also seeds one posting row per active platform. The
  /// artwork itself is attached later (`design_file_url` on the design
  /// endpoint), so this only plans the post.
  Future<SocialPost> createSocialPost({
    required String title,
    required String type,
    required DateTime scheduledDate,
    List<String> postFormats = const ['feed_post'],
    String mediaType = 'image',
    String? scheduledTime,
    String? brief,
    String? hashtags,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/social/posts',
      body: {
        'title': title,
        'type': type,
        'post_format': postFormats.isEmpty ? ['feed_post'] : postFormats,
        'media_type': mediaType,
        'scheduled_date': _day(scheduledDate),
        if (scheduledTime != null && scheduledTime.isNotEmpty)
          'scheduled_time': scheduledTime,
        if (brief != null && brief.isNotEmpty) 'brief': brief,
        if (hashtags != null && hashtags.isNotEmpty) 'hashtags': hashtags,
      },
    );
    return SocialPost.fromJson(_data(body));
  }

  /// PUT /social/posts/{id} — needs social.update. Every field is
  /// `sometimes`; the plan (title, type, format, schedule, brief) only —
  /// [updatePostContent] and [updatePostDesign] own the rest, matching how
  /// the three sit on separate tabs on web.
  Future<SocialPost> updateSocialPost(
    String postId, {
    String? title,
    String? type,
    List<String>? postFormats,
    String? mediaType,
    DateTime? scheduledDate,
    String? scheduledTime,
    String? brief,
    String? hashtags,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/social/posts/$postId',
      body: {
        'title': ?title,
        'type': ?type,
        'post_format': ?postFormats,
        'media_type': ?mediaType,
        if (scheduledDate != null) 'scheduled_date': _day(scheduledDate),
        'scheduled_time': ?scheduledTime,
        'brief': ?brief,
        'hashtags': ?hashtags,
      },
    );
    return SocialPost.fromJson(_data(body));
  }

  /// PATCH /social/posts/{id}/design — needs social.update. [designStatus]
  /// is required by the controller: `pending | in_progress | done`.
  Future<SocialPost> updatePostDesign(
    String postId, {
    required String designStatus,
    String? designNotes,
    String? designFileUrl,
  }) async {
    final body = await _api.patch<Map<String, dynamic>>(
      '/social/posts/$postId/design',
      body: {
        'design_status': designStatus,
        'design_notes': ?designNotes,
        'design_file_url': ?designFileUrl,
      },
    );
    return SocialPost.fromJson(_data(body));
  }

  /// PATCH /social/posts/{id}/content — needs social.update. [contentStatus]
  /// is required by the controller: `pending | ready`.
  Future<SocialPost> updatePostContent(
    String postId, {
    required String contentStatus,
    String? caption,
    String? hashtags,
  }) async {
    final body = await _api.patch<Map<String, dynamic>>(
      '/social/posts/$postId/content',
      body: {
        'content_status': contentStatus,
        'caption': ?caption,
        'hashtags': ?hashtags,
      },
    );
    return SocialPost.fromJson(_data(body));
  }

  /// DELETE /social/posts/{id} — needs social.delete.
  Future<void> deleteSocialPost(String postId) =>
      _api.delete<dynamic>('/social/posts/$postId');

  /// PATCH /social/posts/{id}/platform/{platform} — needs social.update.
  /// Marks the post posted (or not) on one platform and re-derives its status.
  Future<SocialPost> setSocialPostPosted(
    String postId,
    String platform, {
    required bool posted,
    String? postUrl,
  }) async {
    final body = await _api.patch<Map<String, dynamic>>(
      '/social/posts/$postId/platform/$platform',
      body: {
        'posted': posted,
        if (postUrl != null && postUrl.isNotEmpty) 'post_url': postUrl,
      },
    );
    return SocialPost.fromJson(_data(body));
  }

  // ─── Client design orders ───────────────────────────────────────────────
  //
  // A separate work queue from the post planner above: a client asking for
  // a logo, flyer, banner etc., tracked through to delivery. Nothing here
  // seeds a [SocialPost] — the two are unrelated except for sharing the
  // `social.*` permissions and a designer pool.

  /// GET /social/design-orders — needs social.read.
  Future<List<ClientDesignOrder>> socialDesignOrders({
    String? status,
    String? designType,
    String? designerId,
  }) async {
    final body = await _api.get<dynamic>(
      '/social/design-orders',
      query: {
        'status': status,
        'design_type': designType,
        'designer_id': designerId,
      },
    );
    return Paginated.fromJson(body, ClientDesignOrder.fromJson).items;
  }

  /// POST /social/design-orders — needs social.create.
  Future<ClientDesignOrder> createDesignOrder({
    required String title,
    required String designType,
    String? clientId,
    String? description,
    String? referenceUrl,
    String? designerId,
    DateTime? dueDate,
    double? price,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/social/design-orders',
      body: {
        'title': title,
        'design_type': designType,
        'client_id': ?clientId,
        'description': ?description,
        'reference_url': ?referenceUrl,
        'assigned_designer_id': ?designerId,
        if (dueDate != null) 'due_date': _day(dueDate),
        'price': ?price,
      },
    );
    return ClientDesignOrder.fromJson(_data(body));
  }

  /// PUT /social/design-orders/{id} — needs social.update. Every field is
  /// `sometimes`. Setting [status] to `needs_revision` auto-increments the
  /// order's revision count server-side — nothing to send for that beyond
  /// the status itself.
  Future<ClientDesignOrder> updateDesignOrder(
    String id, {
    String? title,
    String? clientId,
    String? designType,
    String? description,
    String? referenceUrl,
    String? designerId,
    String? status,
    DateTime? dueDate,
    String? fileUrl,
    String? revisionNotes,
    double? price,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/social/design-orders/$id',
      body: {
        'title': ?title,
        'client_id': ?clientId,
        'design_type': ?designType,
        'description': ?description,
        'reference_url': ?referenceUrl,
        'assigned_designer_id': ?designerId,
        'status': ?status,
        if (dueDate != null) 'due_date': _day(dueDate),
        'file_url': ?fileUrl,
        'revision_notes': ?revisionNotes,
        'price': ?price,
      },
    );
    return ClientDesignOrder.fromJson(_data(body));
  }

  /// DELETE /social/design-orders/{id} — needs social.delete.
  Future<void> deleteDesignOrder(String id) =>
      _api.delete<dynamic>('/social/design-orders/$id');

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Unwrap `{data: {...}}`, tolerating the endpoints that return the object
  /// at the top level instead.
  static Map<String, dynamic> _data(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

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

  /// `Y-m-d`. Laravel's `date` rule accepts ISO-8601 too, but a bare day avoids
  /// a timezone shifting a scheduled date onto the wrong side of midnight.
  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

/// Permission names for the communications routes, verbatim from
/// routes/api.php middleware. Menu-level names gate a whole screen; the
/// granular ones gate individual actions inside it.
abstract final class CommsPermissions {
  static const sms = 'menu.sms';
  static const broadcast = 'menu.broadcast';

  static const whatsappContactsRead = 'whatsapp_contacts.read';
  static const whatsappContactsCreate = 'whatsapp_contacts.create';
  static const whatsappContactsUpdate = 'whatsapp_contacts.update';
  static const whatsappContactsDelete = 'whatsapp_contacts.delete';
  static const whatsappContactsConvert = 'whatsapp_contacts.convert';
  static const whatsappContactsLog = 'whatsapp_contacts.log';
  static const whatsappContactsViewAll = 'whatsapp_contacts.view_all';
  static const whatsappCampaignsRead = 'whatsapp_campaigns.read';
  static const whatsappCampaignsCreate = 'whatsapp_campaigns.create';
  static const whatsappCampaignsUpdate = 'whatsapp_campaigns.update';
  static const whatsappCampaignsDelete = 'whatsapp_campaigns.delete';

  /// Reassigning a contact means listing `/users`, which is gated separately
  /// from the assign route itself.
  static const settingsUsers = 'settings.users';

  static const socialRead = 'social.read';
  static const socialCreate = 'social.create';
  static const socialUpdate = 'social.update';
  static const socialDelete = 'social.delete';

  /// Platform CRUD and both target endpoints share this one, despite the
  /// name suggesting only targets.
  static const socialTargets = 'social.targets';

  /// `social.settings` is also enforced server-side, on platform
  /// update/delete (`SocialMediaController`). The five below are seeded
  /// permissions used only for tab/section visibility — every actual write
  /// still goes through `socialRead`/`Create`/`Update`/`Delete` above.
  static const socialSettings = 'social.settings';
  static const socialBoard = 'social.board';
  static const socialClientDesigns = 'social.client_designs';
  static const socialDesignWork = 'social.design_work';
  static const socialContent = 'social.content';
  static const socialQa = 'social.qa';
}

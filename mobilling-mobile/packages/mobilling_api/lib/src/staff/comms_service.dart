import '../api_client.dart';
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
    final body = await _api
        .get<Map<String, dynamic>>('/sms/purchases/$purchaseId/status');
    return SmsPurchaseStatus.fromJson(_data(body));
  }

  /// POST /sms/purchases/{id}/retry — needs menu.sms. Returns the payment URL
  /// to reopen, either the stored one or a freshly submitted order.
  Future<String?> retrySmsPurchase(String purchaseId) async {
    final body = await _api
        .post<Map<String, dynamic>>('/sms/purchases/$purchaseId/retry');
    return _data(body)['redirect_url']?.toString();
  }

  /// POST /sms/request-activation — needs menu.sms. Notifies the super admins;
  /// 422 when SMS is already configured. Returns the server's message.
  Future<String> requestSmsActivation() async {
    final body =
        await _api.post<Map<String, dynamic>>('/sms/request-activation');
    return body['message']?.toString() ?? 'Request sent.';
  }

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
  /// Sending is synchronous server-side (a foreach over the recipients), so the
  /// returned tally is final and the call can take a while on a large client
  /// list.
  ///
  /// [subject] and [body] are required for email and both; [smsBody] for sms
  /// and both, capped at 160 characters. Omitting [clientIds] sends to **every**
  /// client with a usable address on the chosen channel — callers should
  /// confirm that with the user first.
  Future<BroadcastResult> sendBroadcast({
    required BroadcastChannel channel,
    String? subject,
    String? body,
    String? smsBody,
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
        if (clientIds != null && clientIds.isNotEmpty) 'client_ids': clientIds,
      },
    );
    return BroadcastResult.fromJson(response);
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
    final body =
        await _api.get<Map<String, dynamic>>('/whatsapp-contacts/stats');
    return WhatsappContactStats.fromJson(body);
  }

  /// POST /whatsapp-contacts/{id}/claim — needs whatsapp_contacts.update.
  /// Takes ownership of an unowned contact; 403 if someone else owns it.
  Future<WhatsappContact> claimWhatsappContact(String contactId) async {
    final body = await _api
        .post<Map<String, dynamic>>('/whatsapp-contacts/$contactId/claim');
    return WhatsappContact.fromJson(body);
  }

  /// GET /whatsapp-campaigns — needs whatsapp_campaigns.read. Unpaginated,
  /// with lead and conversion counts attached.
  Future<List<WhatsappCampaign>> whatsappCampaigns() async {
    final body = await _api.get<List<dynamic>>('/whatsapp-campaigns');
    return Paginated.fromJson(body, WhatsappCampaign.fromJson).items;
  }

  /// GET /whatsapp-contacts/{id}/followups — needs whatsapp_contacts.log.
  /// Newest call first (the relation orders by call_date desc).
  Future<List<WhatsappFollowup>> whatsappFollowups(String contactId) async {
    final body = await _api
        .get<List<dynamic>>('/whatsapp-contacts/$contactId/followups');
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

  // ─── Social media planner ─────────────────────────────────────────────────

  /// GET /social/platforms — needs social.read. The tenant's configured
  /// platforms, in display order.
  Future<List<SocialPlatformConfig>> socialPlatforms() async {
    final body = await _api.get<dynamic>('/social/platforms');
    return Paginated.fromJson(body, SocialPlatformConfig.fromJson).items;
  }

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

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Unwrap `{data: {...}}`, tolerating the endpoints that return the object
  /// at the top level instead.
  static Map<String, dynamic> _data(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
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
  static const whatsappContactsUpdate = 'whatsapp_contacts.update';
  static const whatsappContactsLog = 'whatsapp_contacts.log';
  static const whatsappContactsViewAll = 'whatsapp_contacts.view_all';
  static const whatsappCampaignsRead = 'whatsapp_campaigns.read';

  static const socialRead = 'social.read';
  static const socialCreate = 'social.create';
  static const socialUpdate = 'social.update';
}

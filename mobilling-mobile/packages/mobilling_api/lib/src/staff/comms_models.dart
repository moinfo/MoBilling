/// Models for the staff-side communications area: SMS credits, client
/// broadcasts, the WhatsApp marketing pipeline and the social-media planner.
///
/// These four controllers were written at different times and never
/// standardised on an envelope or on field types, so the parsing here is
/// deliberately tolerant (see `json.dart` for why):
///
///   * `SmsPurchaseController` returns `{data: {...}}`, Laravel's paginator
///     verbatim, or a bare model depending on the method.
///   * `WhatsappContactController::index` returns a bare JSON **array**, as do
///     the campaign and follow-up lists.
///   * `SocialMediaController` wraps everything in `{data: ...}` and serialises
///     a post's platforms as a `keyBy('platform')` **object**, not a list.
///
/// Money columns are `decimal:2` casts, which Laravel serialises as strings —
/// every amount below therefore goes through `money()`.
library;

import '../json.dart';

// ─── SMS ────────────────────────────────────────────────────────────────────

/// A purchasable credit tier (`SmsPackage`). `maxQuantity` is null on the top
/// tier, which is open-ended.
class SmsPackageOption {
  const SmsPackageOption({
    required this.id,
    required this.name,
    required this.pricePerSms,
    required this.minQuantity,
    this.maxQuantity,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final double pricePerSms;
  final int minQuantity;
  final int? maxQuantity;
  final bool isActive;
  final int sortOrder;

  /// Whether [quantity] falls in this tier — mirrors `SmsPackage::forQuantity`
  /// so the UI can show the price before the server confirms it.
  bool covers(int quantity) =>
      quantity >= minQuantity &&
      (maxQuantity == null || quantity <= maxQuantity!);

  factory SmsPackageOption.fromJson(Map<String, dynamic> json) =>
      SmsPackageOption(
        id: json.id(),
        name: json.strOr('name', 'Package'),
        pricePerSms: json.money('price_per_sms'),
        minQuantity: json.count('min_quantity'),
        maxQuantity: json['max_quantity'] == null
            ? null
            : json.count('max_quantity'),
        isActive: json.flag('is_active', fallback: true),
        sortOrder: json.count('sort_order'),
      );
}

/// The reseller balance. A null [balance] is not an error state in itself:
/// `SmsPurchaseController::balance` returns 200 with `sms_balance: null` both
/// when the tenant has no SMS credentials ([message] set) and when the upstream
/// reseller call threw ([error] set).
class SmsBalance {
  const SmsBalance({this.balance, this.message, this.error});

  final int? balance;
  final String? message;
  final String? error;

  bool get isConfigured => balance != null;

  factory SmsBalance.fromJson(Map<String, dynamic> json) => SmsBalance(
        balance: json['sms_balance'] == null ? null : json.count('sms_balance'),
        message: json.str('message'),
        error: json.str('error'),
      );
}

/// One row of purchase history (`SmsPurchase`).
class SmsPurchase {
  const SmsPurchase({
    required this.id,
    required this.smsQuantity,
    required this.pricePerSms,
    required this.totalAmount,
    required this.status,
    this.packageName,
    this.receiptNumber,
    this.orderTrackingId,
    this.redirectUrl,
    this.confirmationCode,
    this.paymentMethodUsed,
    this.completedAt,
    this.createdAt,
  });

  final String id;
  final int smsQuantity;
  final double pricePerSms;
  final double totalAmount;

  /// `pending` | `completed` | `failed`.
  final String status;
  final String? packageName;
  final String? receiptNumber;
  final String? orderTrackingId;

  /// Pesapal hosted-payment page. Present while a purchase is still payable.
  final String? redirectUrl;
  final String? confirmationCode;
  final String? paymentMethodUsed;
  final DateTime? completedAt;
  final DateTime? createdAt;

  bool get isCompleted => status == 'completed';

  /// Retrying only makes sense while the purchase is unpaid.
  bool get isPayable => status != 'completed';

  factory SmsPurchase.fromJson(Map<String, dynamic> json) => SmsPurchase(
        id: json.id(),
        smsQuantity: json.count('sms_quantity'),
        pricePerSms: json.money('price_per_sms'),
        totalAmount: json.money('total_amount'),
        status: json.strOr('status', 'pending'),
        packageName: json.str('package_name'),
        receiptNumber: json.str('receipt_number'),
        orderTrackingId: json.str('order_tracking_id'),
        redirectUrl: json.str('pesapal_redirect_url'),
        confirmationCode: json.str('confirmation_code'),
        paymentMethodUsed: json.str('payment_method_used'),
        completedAt: json.date('completed_at'),
        createdAt: json.date('created_at'),
      );
}

/// Result of POST /sms/checkout — the caller is expected to open
/// [redirectUrl] in a browser to complete payment at Pesapal.
class SmsCheckout {
  const SmsCheckout({
    required this.purchaseId,
    this.redirectUrl,
    this.orderTrackingId,
  });

  final String purchaseId;
  final String? redirectUrl;
  final String? orderTrackingId;

  factory SmsCheckout.fromJson(Map<String, dynamic> json) => SmsCheckout(
        purchaseId: json.id('purchase_id'),
        redirectUrl: json.str('redirect_url'),
        orderTrackingId: json.str('order_tracking_id'),
      );
}

/// Result of the status poll, which also nudges the server to re-check Pesapal.
class SmsPurchaseStatus {
  const SmsPurchaseStatus({
    required this.id,
    required this.status,
    required this.smsQuantity,
    required this.totalAmount,
    this.description,
    this.confirmationCode,
  });

  final String id;
  final String status;
  final int smsQuantity;
  final double totalAmount;
  final String? description;
  final String? confirmationCode;

  bool get isCompleted => status == 'completed';

  factory SmsPurchaseStatus.fromJson(Map<String, dynamic> json) =>
      SmsPurchaseStatus(
        id: json.id(),
        status: json.strOr('status', 'pending'),
        smsQuantity: json.count('sms_quantity'),
        totalAmount: json.money('total_amount'),
        description: json.str('payment_status_description'),
        confirmationCode: json.str('confirmation_code'),
      );
}

// ─── Broadcasts ─────────────────────────────────────────────────────────────

/// Channels a broadcast can go out on, verbatim from
/// `BroadcastController::send`'s `in:email,sms,both` rule.
enum BroadcastChannel {
  email('email', 'Email'),
  sms('sms', 'SMS'),
  both('both', 'Email + SMS');

  const BroadcastChannel(this.value, this.label);

  final String value;
  final String label;

  bool get includesEmail => this != BroadcastChannel.sms;
  bool get includesSms => this != BroadcastChannel.email;

  static BroadcastChannel parse(String? value) =>
      BroadcastChannel.values.firstWhere(
        (c) => c.value == value,
        orElse: () => BroadcastChannel.email,
      );
}

/// A sent broadcast, with its delivery tally.
class Broadcast {
  const Broadcast({
    required this.id,
    required this.channel,
    required this.totalRecipients,
    required this.sentCount,
    required this.failedCount,
    this.subject,
    this.body,
    this.smsBody,
    this.senderName,
    this.clientIds,
    this.createdAt,
  });

  final String id;
  final BroadcastChannel channel;
  final int totalRecipients;
  final int sentCount;
  final int failedCount;
  final String? subject;
  final String? body;
  final String? smsBody;
  final String? senderName;

  /// Null when the broadcast went to every eligible client.
  final List<String>? clientIds;
  final DateTime? createdAt;

  bool get wasTargeted => clientIds != null && clientIds!.isNotEmpty;

  /// A status word for [StatusChip]: nothing delivered reads as failed, a
  /// partial delivery as partial.
  String get deliveryStatus {
    if (sentCount == 0 && totalRecipients > 0) return 'failed';
    if (failedCount > 0) return 'partial';
    return 'completed';
  }

  factory Broadcast.fromJson(Map<String, dynamic> json) => Broadcast(
        id: json.id(),
        channel: BroadcastChannel.parse(json.str('channel')),
        totalRecipients: json.count('total_recipients'),
        sentCount: json.count('sent_count'),
        failedCount: json.count('failed_count'),
        subject: json.str('subject'),
        body: json.str('body'),
        smsBody: json.str('sms_body'),
        senderName: json.object('sender')?.str('name'),
        clientIds: json['client_ids'] == null ? null : json.strings('client_ids'),
        createdAt: json.date('created_at'),
      );
}

/// The tally returned straight after sending — the send is synchronous
/// server-side, so these numbers are final.
class BroadcastResult {
  const BroadcastResult({
    required this.totalRecipients,
    required this.sentCount,
    required this.failedCount,
    this.broadcastId,
  });

  final int totalRecipients;
  final int sentCount;
  final int failedCount;
  final String? broadcastId;

  factory BroadcastResult.fromJson(Map<String, dynamic> json) =>
      BroadcastResult(
        totalRecipients: json.count('total_recipients'),
        sentCount: json.count('sent_count'),
        failedCount: json.count('failed_count'),
        broadcastId: json.str('broadcast_id'),
      );
}

// ─── WhatsApp pipeline ──────────────────────────────────────────────────────

/// Pipeline stage of a WhatsApp lead. Matches the `label` enum and the order
/// the web board shows them in.
enum WhatsappLabel {
  lead('lead', 'Lead'),
  newCustomer('new_customer', 'New customer'),
  newOrder('new_order', 'New order'),
  followUp('follow_up', 'Follow up'),
  pendingPayment('pending_payment', 'Pending payment'),
  paid('paid', 'Paid'),
  orderComplete('order_complete', 'Order complete');

  const WhatsappLabel(this.value, this.label);

  final String value;
  final String label;

  static WhatsappLabel? tryParse(String? value) {
    for (final l in WhatsappLabel.values) {
      if (l.value == value) return l;
    }
    return null;
  }

  static String labelFor(String? value) =>
      tryParse(value)?.label ?? _humanise(value);
}

/// Where a lead came from (`source` enum).
enum WhatsappSource {
  whatsappAd('whatsapp_ad', 'WhatsApp ad'),
  instagram('instagram', 'Instagram'),
  facebook('facebook', 'Facebook'),
  socialMedia('social_media', 'Other social media'),
  direct('direct', 'Direct'),
  referral('referral', 'Referral'),
  other('other', 'Other');

  const WhatsappSource(this.value, this.label);

  final String value;
  final String label;

  static WhatsappSource? tryParse(String? value) {
    for (final s in WhatsappSource.values) {
      if (s.value == value) return s;
    }
    return null;
  }

  static String labelFor(String? value) =>
      tryParse(value)?.label ?? _humanise(value);
}

/// Outcome of a logged follow-up call (`WhatsappFollowup::outcome`).
enum FollowupOutcome {
  answered('answered', 'Answered'),
  noAnswer('no_answer', 'No answer'),
  callback('callback', 'Callback'),
  interested('interested', 'Interested'),
  notInterested('not_interested', 'Not interested'),
  converted('converted', 'Converted');

  const FollowupOutcome(this.value, this.label);

  final String value;
  final String label;

  static FollowupOutcome? tryParse(String? value) {
    for (final o in FollowupOutcome.values) {
      if (o.value == value) return o;
    }
    return null;
  }

  static String labelFor(String? value) =>
      tryParse(value)?.label ?? _humanise(value);
}

/// A lead in the WhatsApp marketing pipeline.
class WhatsappContact {
  const WhatsappContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.label,
    required this.source,
    required this.services,
    this.isImportant = false,
    this.notes,
    this.campaignId,
    this.campaignName,
    this.clientId,
    this.clientName,
    this.assignedUserName,
    this.createdBy,
    this.creatorName,
    this.nextFollowupDate,
    this.createdAt,
  });

  final String id;
  final String name;
  final String phone;

  /// Raw enum value; use [WhatsappLabel.labelFor] to display it. Kept as a
  /// string because the enum has been extended by migration before.
  final String label;
  final String source;
  final List<String> services;
  final bool isImportant;
  final String? notes;
  final String? campaignId;
  final String? campaignName;

  /// Set once the lead has been converted into a billing client.
  final String? clientId;
  final String? clientName;
  final String? assignedUserName;

  /// Owner. Null means the contact sits in the shared pool and can be claimed.
  final String? createdBy;
  final String? creatorName;
  final DateTime? nextFollowupDate;
  final DateTime? createdAt;

  bool get isConverted => clientId != null;

  /// True when a follow-up is booked for today or earlier.
  bool get isFollowupDue {
    final due = nextFollowupDate;
    if (due == null) return false;
    final today = DateTime.now();
    return !DateTime(due.year, due.month, due.day)
        .isAfter(DateTime(today.year, today.month, today.day));
  }

  factory WhatsappContact.fromJson(Map<String, dynamic> json) =>
      WhatsappContact(
        id: json.id(),
        name: json.strOr('name', '—'),
        phone: json.strOr('phone', ''),
        label: json.strOr('label', 'lead'),
        source: json.strOr('source', 'other'),
        services: json.strings('services'),
        isImportant: json.flag('is_important'),
        notes: json.str('notes'),
        campaignId: json.str('campaign_id'),
        campaignName: json.object('campaign')?.str('name'),
        clientId: json.str('client_id'),
        clientName: json.object('client')?.str('name'),
        assignedUserName: json.object('assigned_user')?.str('name'),
        createdBy: json.str('created_by'),
        creatorName: json.object('creator')?.str('name'),
        nextFollowupDate: json.date('next_followup_date'),
        createdAt: json.date('created_at'),
      );
}

/// Pipeline counts from `/whatsapp-contacts/stats`, already scoped server-side
/// to what the signed-in user may see.
class WhatsappContactStats {
  const WhatsappContactStats({
    required this.total,
    required this.converted,
    required this.byLabel,
    required this.bySource,
  });

  final int total;
  final int converted;
  final Map<String, int> byLabel;
  final Map<String, int> bySource;

  factory WhatsappContactStats.fromJson(Map<String, dynamic> json) =>
      WhatsappContactStats(
        total: json.count('total'),
        converted: json.count('converted'),
        byLabel: _countMap(json['by_label']),
        bySource: _countMap(json['by_source']),
      );
}

/// A paid WhatsApp campaign, with the lead counts the index adds via
/// `withCount`.
class WhatsappCampaign {
  const WhatsappCampaign({
    required this.id,
    required this.name,
    required this.budget,
    required this.leadsCount,
    required this.convertedCount,
    this.startDate,
    this.endDate,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String name;
  final double budget;
  final int leadsCount;
  final int convertedCount;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? notes;
  final DateTime? createdAt;

  /// Spend per lead, or null when the campaign has yet to produce one.
  double? get costPerLead => leadsCount == 0 ? null : budget / leadsCount;

  /// Spend per converted client — the number the campaign is actually judged
  /// on. Null until the first conversion.
  double? get costPerConversion =>
      convertedCount == 0 ? null : budget / convertedCount;

  factory WhatsappCampaign.fromJson(Map<String, dynamic> json) =>
      WhatsappCampaign(
        id: json.id(),
        name: json.strOr('name', '—'),
        budget: json.money('budget'),
        leadsCount: json.count('leads_count'),
        convertedCount: json.count('converted_count'),
        startDate: json.date('start_date'),
        endDate: json.date('end_date'),
        notes: json.str('notes'),
        createdAt: json.date('created_at'),
      );
}

/// One logged call against a contact.
class WhatsappFollowup {
  const WhatsappFollowup({
    required this.id,
    required this.outcome,
    this.contactId,
    this.callDate,
    this.notes,
    this.nextFollowupDate,
    this.userName,
    this.createdAt,
  });

  final String id;
  final String outcome;
  final String? contactId;
  final DateTime? callDate;
  final String? notes;
  final DateTime? nextFollowupDate;
  final String? userName;
  final DateTime? createdAt;

  factory WhatsappFollowup.fromJson(Map<String, dynamic> json) =>
      WhatsappFollowup(
        id: json.id(),
        outcome: json.strOr('outcome', 'answered'),
        contactId: json.str('whatsapp_contact_id'),
        callDate: json.date('call_date'),
        notes: json.str('notes'),
        nextFollowupDate: json.date('next_followup_date'),
        userName: json.object('user')?.str('name'),
        createdAt: json.date('created_at'),
      );
}

// ─── Social media planner ───────────────────────────────────────────────────

/// A tenant-configured platform. Platforms are rows, not a hardcoded enum —
/// `storePost` seeds one posting row per active platform.
class SocialPlatformConfig {
  const SocialPlatformConfig({
    required this.id,
    required this.name,
    required this.label,
    this.color,
    this.icon,
    this.profileUrl,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;

  /// Slug used as the `platform` key on posting rows, e.g. `instagram`.
  final String name;
  final String label;
  final String? color;
  final String? icon;
  final String? profileUrl;
  final bool isActive;
  final int sortOrder;

  factory SocialPlatformConfig.fromJson(Map<String, dynamic> json) =>
      SocialPlatformConfig(
        id: json.id(),
        name: json.strOr('name', ''),
        label: json.strOr('label', json.strOr('name', '—')),
        color: json.str('color'),
        icon: json.str('icon'),
        profileUrl: json.str('profile_url'),
        isActive: json.flag('is_active', fallback: true),
        sortOrder: json.count('sort_order'),
      );
}

/// Whether a post has gone out on one platform.
class SocialPostPlatform {
  const SocialPostPlatform({
    required this.platform,
    required this.posted,
    this.postedAt,
    this.postUrl,
  });

  final String platform;
  final bool posted;
  final DateTime? postedAt;
  final String? postUrl;

  factory SocialPostPlatform.fromJson(Map<String, dynamic> json) =>
      SocialPostPlatform(
        platform: json.strOr('platform', ''),
        posted: json.flag('posted'),
        postedAt: json.date('posted_at'),
        postUrl: json.str('post_url'),
      );
}

/// A planned or published post.
class SocialPost {
  const SocialPost({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.designStatus,
    required this.contentStatus,
    required this.postFormats,
    required this.platforms,
    this.mediaType = 'image',
    this.scheduledDate,
    this.scheduledTime,
    this.brief,
    this.caption,
    this.hashtags,
    this.designFileUrl,
    this.designNotes,
    this.createdAt,
  });

  final String id;
  final String title;

  /// `product_education` | `holiday` | `employee_birthday` | `promotion` |
  /// `announcement` | `general`.
  final String type;

  /// Derived server-side by `SocialPost::syncStatus`: planned, designing,
  /// content_ready, partial_posted, posted.
  final String status;

  /// `pending` | `in_progress` | `done`.
  final String designStatus;

  /// `pending` | `ready`.
  final String contentStatus;

  /// One or more of feed_post, reel, story, carousel.
  final List<String> postFormats;

  /// One row per configured platform, sorted by platform name for a stable
  /// render order (the API hands these over as an unordered keyed object).
  final List<SocialPostPlatform> platforms;
  final String mediaType;
  final DateTime? scheduledDate;

  /// `HH:mm`, already trimmed server-side.
  final String? scheduledTime;
  final String? brief;
  final String? caption;
  final String? hashtags;
  final String? designFileUrl;
  final String? designNotes;
  final DateTime? createdAt;

  bool get isVideo => mediaType == 'video';

  int get postedCount => platforms.where((p) => p.posted).length;

  factory SocialPost.fromJson(Map<String, dynamic> json) {
    final formats = json.strings('post_format');
    return SocialPost(
      id: json.id(),
      title: json.strOr('title', '—'),
      type: json.strOr('type', 'general'),
      status: json.strOr('status', 'planned'),
      designStatus: json.strOr('design_status', 'pending'),
      contentStatus: json.strOr('content_status', 'pending'),
      postFormats: formats.isEmpty ? const ['feed_post'] : formats,
      platforms: _platformRows(json['platforms']),
      mediaType: json.strOr('media_type', 'image'),
      scheduledDate: json.date('scheduled_date'),
      scheduledTime: json.str('scheduled_time'),
      brief: json.str('brief'),
      caption: json.str('caption'),
      hashtags: json.str('hashtags'),
      designFileUrl: json.str('design_file_url'),
      designNotes: json.str('design_notes'),
      createdAt: json.date('created_at'),
    );
  }

  /// `formatPost` runs `->keyBy('platform')`, which serialises as an object
  /// keyed by platform name. An empty collection, however, serialises as `[]`,
  /// so both shapes have to be accepted.
  static List<SocialPostPlatform> _platformRows(Object? raw) {
    final rows = <SocialPostPlatform>[];

    if (raw is List) {
      for (final entry in raw.whereType<Map>()) {
        rows.add(SocialPostPlatform.fromJson(Map<String, dynamic>.from(entry)));
      }
    } else if (raw is Map) {
      raw.forEach((key, value) {
        if (value is! Map) return;
        final row = Map<String, dynamic>.from(value);
        // Fall back to the map key when the row somehow omits its own name.
        row['platform'] ??= key;
        rows.add(SocialPostPlatform.fromJson(row));
      });
    }

    rows.sort((a, b) => a.platform.compareTo(b.platform));
    return rows;
  }
}

/// The tenant's weekly output target.
class SocialTarget {
  const SocialTarget({
    required this.id,
    required this.imageTarget,
    required this.videoTarget,
    required this.activeDays,
    this.effectiveFrom,
  });

  final String id;
  final int imageTarget;
  final int videoTarget;

  /// ISO weekdays, 1 = Monday.
  final List<int> activeDays;
  final DateTime? effectiveFrom;

  factory SocialTarget.fromJson(Map<String, dynamic> json) => SocialTarget(
        id: json.id(),
        imageTarget: json.count('image_target'),
        videoTarget: json.count('video_target'),
        activeDays: _intList(json['active_days']),
        effectiveFrom: json.date('effective_from'),
      );
}

/// One day of the weekly summary.
class SocialDailyBreakdown {
  const SocialDailyBreakdown({
    required this.dayName,
    required this.isActive,
    required this.images,
    required this.videos,
    required this.total,
    this.date,
  });

  final String dayName;

  /// Whether the day is in the target's active set — an inactive day with no
  /// posts is on plan, not a miss.
  final bool isActive;
  final int images;
  final int videos;
  final int total;
  final DateTime? date;

  factory SocialDailyBreakdown.fromJson(Map<String, dynamic> json) =>
      SocialDailyBreakdown(
        dayName: json.strOr('day_name', '—'),
        isActive: json.flag('is_active', fallback: true),
        images: json.count('images'),
        videos: json.count('videos'),
        total: json.count('total'),
        date: json.date('date'),
      );
}

/// Target vs actual for one week.
class SocialWeeklySummary {
  const SocialWeeklySummary({
    required this.imageAchieved,
    required this.videoAchieved,
    required this.daily,
    this.weekStart,
    this.weekEnd,
    this.target,
  });

  final int imageAchieved;
  final int videoAchieved;
  final List<SocialDailyBreakdown> daily;
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final SocialTarget? target;

  factory SocialWeeklySummary.fromJson(Map<String, dynamic> json) {
    final target = json.object('target');
    return SocialWeeklySummary(
      imageAchieved: json.count('image_achieved'),
      videoAchieved: json.count('video_achieved'),
      daily: json.list('daily', SocialDailyBreakdown.fromJson),
      weekStart: json.date('week_start'),
      weekEnd: json.date('week_end'),
      target: target == null ? null : SocialTarget.fromJson(target),
    );
  }
}

/// Display labels for the raw social-media enums, mirroring
/// `mobilling-ui/src/api/socialMedia.ts` so both clients read alike.
abstract final class SocialLabels {
  static const postTypes = <String, String>{
    'product_education': 'Product education',
    'holiday': 'Holiday wishes',
    'employee_birthday': 'Employee birthday',
    'promotion': 'Promotion',
    'announcement': 'Announcement',
    'general': 'General',
  };

  static const postFormats = <String, String>{
    'feed_post': 'Feed post',
    'reel': 'Reel',
    'story': 'Story',
    'carousel': 'Carousel',
  };

  static const postStatuses = <String, String>{
    'planned': 'Planned',
    'designing': 'Designing',
    'content_ready': 'Content ready',
    'partial_posted': 'Partly posted',
    'posted': 'Posted',
  };

  static String postType(String? value) => postTypes[value] ?? _humanise(value);

  static String postFormat(String? value) =>
      postFormats[value] ?? _humanise(value);

  static String postStatus(String? value) =>
      postStatuses[value] ?? _humanise(value);
}

// ─── Shared helpers ─────────────────────────────────────────────────────────

/// `snake_case` -> `Snake case`, for enum values that outgrew their label map.
String _humanise(String? value) {
  if (value == null || value.isEmpty) return '—';
  final words = value.replaceAll('_', ' ').trim();
  return words[0].toUpperCase() + words.substring(1);
}

/// `pluck('count', 'label')` yields an object of counts, but an *empty* result
/// serialises as `[]` — hence the list branch.
Map<String, int> _countMap(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, int>{};
  raw.forEach((key, value) => out[key.toString()] = readInt(value));
  return out;
}

List<int> _intList(Object? raw) {
  if (raw is! List) return const [];
  return raw.map((e) => readInt(e)).toList();
}

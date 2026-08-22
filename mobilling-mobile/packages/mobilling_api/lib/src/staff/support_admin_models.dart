/// Staff-side support content (canned replies, announcements, knowledgebase)
/// and service administration (hosting accounts, domains).
///
/// These are the *staff* shapes and they differ from the portal equivalents in
/// `portal/support_models.dart`: staff see unpublished drafts, sort order and
/// article counts, and the hosting/domain rows carry the owning client.
library;

import '../json.dart';

// ---------------------------------------------------------------------------
// Canned replies — CannedReplyController
// ---------------------------------------------------------------------------

class CannedReply {
  const CannedReply({
    required this.id,
    required this.title,
    required this.body,
    this.updatedAt,
  });

  final String id;
  final String title;

  /// Plain text, pasted straight into a ticket reply.
  final String body;
  final DateTime? updatedAt;

  factory CannedReply.fromJson(Map<String, dynamic> json) => CannedReply(
        id: json.id(),
        title: json.strOr('title', '—'),
        body: json.strOr('body', ''),
        updatedAt: json.date('updated_at'),
      );
}

// ---------------------------------------------------------------------------
// Announcements — AnnouncementController (staff manage)
// ---------------------------------------------------------------------------

class StaffAnnouncement {
  const StaffAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.isPublished,
    this.publishedAt,
    this.createdAt,
  });

  final String id;
  final String title;

  /// HTML from the tenant's editor.
  final String body;

  /// Staff see drafts too — the portal endpoint only returns published ones.
  final bool isPublished;
  final DateTime? publishedAt;
  final DateTime? createdAt;

  /// Status word the shared [StatusChip] understands.
  String get status => isPublished ? 'active' : 'draft';

  factory StaffAnnouncement.fromJson(Map<String, dynamic> json) =>
      StaffAnnouncement(
        id: json.id(),
        title: json.strOr('title', '—'),
        body: json.strOr('body', ''),
        isPublished: json.flag('is_published'),
        publishedAt: json.date('published_at'),
        createdAt: json.date('created_at'),
      );
}

// ---------------------------------------------------------------------------
// Knowledgebase — KbCategoryController / KbArticleController
// ---------------------------------------------------------------------------

class StaffKbCategory {
  const StaffKbCategory({
    required this.id,
    required this.name,
    required this.isActive,
    required this.articlesCount,
    required this.sortOrder,
    this.slug,
    this.description,
  });

  final String id;
  final String name;
  final bool isActive;
  final int articlesCount;
  final int sortOrder;
  final String? slug;
  final String? description;

  factory StaffKbCategory.fromJson(Map<String, dynamic> json) =>
      StaffKbCategory(
        id: json.id(),
        name: json.strOr('name', '—'),
        isActive: json.flag('is_active', fallback: true),
        articlesCount: json.count('articles_count'),
        sortOrder: json.count('sort_order'),
        slug: json.str('slug'),
        description: json.str('description'),
      );
}

class StaffKbArticle {
  const StaffKbArticle({
    required this.id,
    required this.title,
    required this.body,
    required this.isPublished,
    required this.views,
    required this.sortOrder,
    this.categoryId,
    this.categoryName,
    this.slug,
  });

  final String id;
  final String title;

  /// HTML body.
  final String body;
  final bool isPublished;
  final int views;
  final int sortOrder;

  /// Null for uncategorised articles, which the portal buckets as "General".
  final String? categoryId;
  final String? categoryName;
  final String? slug;

  String get status => isPublished ? 'active' : 'draft';

  factory StaffKbArticle.fromJson(Map<String, dynamic> json) => StaffKbArticle(
        id: json.id(),
        title: json.strOr('title', '—'),
        body: json.strOr('body', ''),
        isPublished: json.flag('is_published'),
        views: json.count('views'),
        sortOrder: json.count('sort_order'),
        categoryId: json.str('kb_category_id'),
        categoryName: json.str('category_name'),
        slug: json.str('slug'),
      );
}

// ---------------------------------------------------------------------------
// Hosting accounts — HostingAccountController (staff)
// ---------------------------------------------------------------------------

/// A provisioned hosting account, tenant-wide.
///
/// The index returns the raw Eloquent model with `server` and
/// `subscription.client` eager-loaded, so usage figures come out of the `meta`
/// JSON column exactly as cPanel reported them (strings like "1,240M") and are
/// displayed rather than parsed.
class StaffHostingAccount {
  const StaffHostingAccount({
    required this.id,
    required this.status,
    this.domain,
    this.cpanelUsername,
    this.package,
    this.clientName,
    this.serverName,
    this.serverHostname,
    this.diskUsed,
    this.diskLimit,
    this.lastSyncedAt,
    this.subscriptionId,
  });

  final String id;
  final String status;
  final String? domain;
  final String? cpanelUsername;
  final String? package;
  final String? clientName;
  final String? serverName;
  final String? serverHostname;
  final String? diskUsed;
  final String? diskLimit;
  final DateTime? lastSyncedAt;

  /// Needed for the hosting-services actions, which key off the subscription
  /// rather than the account.
  final String? subscriptionId;

  bool get isActive => status == 'active';
  bool get isSuspended => status == 'suspended';

  factory StaffHostingAccount.fromJson(Map<String, dynamic> json) {
    final meta = json.object('meta');
    final server = json.object('server');
    final subscription = json.object('subscription');
    return StaffHostingAccount(
      id: json.id(),
      status: json.strOr('status', 'active'),
      domain: json.str('domain'),
      cpanelUsername: json.str('cpanel_username'),
      // meta.plan is the live cPanel package; the column is the ordered one.
      package: meta?.str('plan') ?? json.str('package'),
      clientName: subscription?.object('client')?.str('name'),
      serverName: server?.str('name'),
      serverHostname: server?.str('hostname'),
      diskUsed: meta?.str('disk_used'),
      diskLimit: meta?.str('disk_limit'),
      lastSyncedAt: json.date('last_synced_at'),
      subscriptionId: json.str('client_subscription_id'),
    );
  }
}

/// One line from an account's provisioning log.
class ProvisioningLogEntry {
  const ProvisioningLogEntry({
    required this.id,
    required this.action,
    required this.success,
    this.message,
    this.createdAt,
  });

  final String id;
  final String action;
  final bool success;
  final String? message;
  final DateTime? createdAt;

  factory ProvisioningLogEntry.fromJson(Map<String, dynamic> json) =>
      ProvisioningLogEntry(
        id: json.id(),
        action: json.strOr('action', '—'),
        // `ProvisioningLog` rows carry `status: success|failed` and the WHM
        // error text under `error` (see WhmService::log).
        success: json.str('status') == 'success',
        message: json.str('error') ?? json.str('message'),
        createdAt: json.date('created_at'),
      );
}

// ---------------------------------------------------------------------------
// Domains — DomainController (staff)
// ---------------------------------------------------------------------------

class StaffDomain {
  const StaffDomain({
    required this.id,
    required this.name,
    required this.status,
    required this.autoRenew,
    this.clientName,
    this.clientId,
    this.registrarName,
    this.registeredAt,
    this.expiresAt,
    this.unmanaged = false,
  });

  final String id;
  final String name;
  final String status;
  final bool autoRenew;
  final String? clientName;
  final String? clientId;
  final String? registrarName;
  final DateTime? registeredAt;
  final DateTime? expiresAt;

  /// Imported / manually renewed: registry actions are unavailable.
  final bool unmanaged;

  /// Active and inside the 45-day window the backend uses everywhere.
  bool get expiringSoon {
    final expiry = expiresAt;
    if (status != 'active' || expiry == null) return false;
    return expiry.difference(DateTime.now()).inDays <= 45;
  }

  factory StaffDomain.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    final registrar = json.object('registrar_account');
    final meta = json.object('meta');
    return StaffDomain(
      id: json.id(),
      name: json.strOr('name', '—'),
      status: json.strOr('status', 'active'),
      autoRenew: json.flag('auto_renew'),
      clientName: client?.str('name'),
      clientId: json.str('client_id') ?? client?.str('id'),
      registrarName: registrar?.str('name'),
      registeredAt: json.date('registered_at'),
      expiresAt: json.date('expires_at'),
      unmanaged: meta?.flag('unmanaged') ?? false,
    );
  }
}

class StaffDomainStats {
  const StaffDomainStats({
    required this.total,
    required this.active,
    required this.pending,
    required this.expired,
    required this.expiringSoon,
    required this.autoRenew,
  });

  final int total;
  final int active;
  final int pending;
  final int expired;
  final int expiringSoon;
  final int autoRenew;

  factory StaffDomainStats.fromJson(Map<String, dynamic> json) =>
      StaffDomainStats(
        total: json.count('total'),
        active: json.count('active'),
        pending: json.count('pending'),
        expired: json.count('expired'),
        expiringSoon: json.count('expiring_soon'),
        autoRenew: json.count('auto_renew'),
      );
}

/// A domain's nameservers plus whether this client may change them.
class StaffNameservers {
  const StaffNameservers({required this.nameservers, required this.editable});

  final List<String> nameservers;
  final bool editable;

  factory StaffNameservers.fromJson(Map<String, dynamic> json) =>
      StaffNameservers(
        nameservers: json.strings('nameservers'),
        editable: json.flag('editable', fallback: true),
      );
}

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
    this.pendingAction,
    this.sponsoringRegistrar,
    this.subscriptionLabel,
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

  /// `meta.pending_action` — the register/transfer/renew a paid invoice is
  /// waiting on, and the only thing `/retry` can re-run.
  final String? pendingAction;

  /// `meta.sponsoring_registrar` — the handle the registry itself reports,
  /// stamped by the `domains:sync` command. Null until a sync has confirmed it.
  final String? sponsoringRegistrar;

  /// Only present on the show route, which loads the subscription.
  final String? subscriptionLabel;

  /// Active and inside the 45-day window the backend uses everywhere.
  bool get expiringSoon {
    final expiry = expiresAt;
    if (status != 'active' || expiry == null) return false;
    return expiry.difference(DateTime.now()).inDays <= 45;
  }

  /// Live at the registry — the states that accept a renewal or an auto-renew
  /// toggle (`DomainController::setAutoRenew`, `DomainBillingService`).
  bool get isLive => status == 'active' || status == 'expired';

  /// `/retry` returns 422 unless both of these hold.
  bool get canRetry => status == 'failed' && pendingAction != null;

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
      pendingAction: meta?.str('pending_action'),
      sponsoringRegistrar: meta?.str('sponsoring_registrar'),
      subscriptionLabel: json.object('subscription')?.str('label'),
    );
  }
}

/// One line of a domain's registry log (`GET /domains/{id}/logs`, newest 50).
///
/// `action` is either a verb the app wrote (`added_existing`,
/// `auth_info_revealed`) or the raw EPP path the driver called
/// (`/domains/renew/…`), so [label] translates both — the same mapping as the
/// web's `describeDomainAction`.
class StaffDomainLog {
  const StaffDomainLog({
    required this.id,
    required this.action,
    required this.success,
    this.error,
    this.createdAt,
  });

  final String id;
  final String action;
  final bool success;

  /// The registry's rejection text, when the call failed.
  final String? error;
  final DateTime? createdAt;

  String get label {
    switch (action) {
      case 'auth_info_revealed':
        return 'Transfer code viewed';
      case 'auth_info_generated':
        return 'Transfer code generated';
      case 'nameservers_changed':
        return 'Nameservers changed';
      case 'added_existing':
        return 'Added as an existing domain';
    }
    if (action.contains('/nssets/')) {
      if (action.contains('/update/')) return 'Nameserver set updated';
      if (action.contains('/create')) return 'Nameserver set created';
      return 'Nameserver lookup';
    }
    if (action.contains('/info/')) return 'Registry sync check';
    if (action.contains('/renew/')) return 'Registry renewal';
    if (action.contains('/register/')) return 'Domain registration';
    if (action.contains('/transfer/')) return 'Transfer request';
    if (action.contains('/check/')) return 'Availability check';
    if (action.contains('/update/')) return 'Registry update';
    return action.replaceAll('_', ' ');
  }

  factory StaffDomainLog.fromJson(Map<String, dynamic> json) => StaffDomainLog(
        id: json.id(),
        action: json.strOr('action', '—'),
        // DomainLog rows carry `status: success|failed` and the registry's
        // message under `error`.
        success: json.str('status') == 'success',
        error: json.str('error'),
        createdAt: json.date('created_at'),
      );
}

/// Prepaid credit held at the registrar for one zone. Real money: the registry
/// draws it on every register and renew.
class RegistrarZoneCredit {
  const RegistrarZoneCredit({required this.zone, required this.credit});

  /// Without the leading dot — "co.tz", "or.tz".
  final String zone;
  final double credit;

  factory RegistrarZoneCredit.fromJson(Map<String, dynamic> json) =>
      RegistrarZoneCredit(
        zone: json.strOr('zone', '—'),
        credit: json.money('credit'),
      );
}

/// A zone-to-zone credit move TZNIC has yet to action. Requesting one is a
/// `domains.settings` action the web owns; the app shows them so staff know
/// why a balance has not moved yet.
class RegistrarCreditTransferRequest {
  const RegistrarCreditTransferRequest({
    required this.id,
    required this.fromZone,
    required this.toZone,
    required this.amount,
    this.requestedBy,
    this.createdAt,
  });

  final String id;
  final String fromZone;
  final String toZone;
  final double amount;
  final String? requestedBy;
  final DateTime? createdAt;

  factory RegistrarCreditTransferRequest.fromJson(Map<String, dynamic> json) =>
      RegistrarCreditTransferRequest(
        id: json.id(),
        fromZone: json.strOr('from_zone', '—'),
        toZone: json.strOr('to_zone', '—'),
        amount: json.money('amount'),
        requestedBy: json.str('requested_by'),
        createdAt: json.date('created_at'),
      );
}

/// `GET /domains/registrar-credit` — the live TZNIC balance, cached 5 minutes
/// server-side. [ok] is false when the registrar could not be reached, in
/// which case [zones] is empty and [error] carries the reason.
class StaffRegistrarCredit {
  const StaffRegistrarCredit({
    required this.ok,
    required this.zones,
    required this.total,
    required this.fundedCount,
    required this.low,
    required this.pendingTransfers,
    this.checkedAt,
    this.error,
  });

  final bool ok;

  /// Every zone the registry runs, most of them at zero.
  final List<RegistrarZoneCredit> zones;

  /// Sum across the funded zones only.
  final double total;
  final int fundedCount;

  /// Funded zones under the server's threshold (50,000 by default) — these
  /// need a top-up before the next renewal.
  final List<String> low;
  final List<RegistrarCreditTransferRequest> pendingTransfers;
  final DateTime? checkedAt;
  final String? error;

  List<RegistrarZoneCredit> get funded =>
      zones.where((z) => z.credit > 0).toList();

  bool isLow(String zone) => low.contains(zone);

  factory StaffRegistrarCredit.fromJson(Map<String, dynamic> json) =>
      StaffRegistrarCredit(
        ok: json.flag('ok'),
        zones: json.list('zones', RegistrarZoneCredit.fromJson),
        total: json.money('total'),
        fundedCount: json.count('funded_count'),
        low: json.strings('low'),
        pendingTransfers: json.list(
          'pending_transfers',
          RegistrarCreditTransferRequest.fromJson,
        ),
        checkedAt: json.date('checked_at'),
        error: json.str('error'),
      );
}

/// `GET /domains/whois?name=` — a live port-43 lookup at the TZNIC registry,
/// for .tz names only (anything else is a 422).
class StaffWhoisResult {
  const StaffWhoisResult({
    required this.domain,
    required this.found,
    required this.statuses,
    required this.nameservers,
    required this.isOurs,
    this.registrar,
    this.registrant,
    this.registered,
    this.changed,
    this.expire,
    this.nsset,
    this.ourRegistrar,
    this.raw,
  });

  final String domain;

  /// False when the registry has no record — the name is available.
  final bool found;

  /// Registry status words, e.g. `expired`, `serverDeleteProhibited`.
  final List<String> statuses;
  final List<String> nameservers;

  /// The registry names us as the sponsoring registrar.
  final bool isOurs;

  final String? registrar;
  final String? registrant;

  /// Dates arrive as the registry's own strings; shown verbatim rather than
  /// re-parsed, so a WHOIS reads the way the registry wrote it.
  final String? registered;
  final String? changed;
  final String? expire;
  final String? nsset;

  /// Our own registrar handle, for the "is this ours?" comparison.
  final String? ourRegistrar;
  final String? raw;

  factory StaffWhoisResult.fromJson(Map<String, dynamic> json) =>
      StaffWhoisResult(
        domain: json.strOr('domain', '—'),
        found: json.flag('found'),
        statuses: json.strings('statuses'),
        nameservers: json.strings('nameservers'),
        isOurs: json.flag('is_ours'),
        registrar: json.str('registrar'),
        registrant: json.str('registrant'),
        registered: json.str('registered'),
        changed: json.str('changed'),
        expire: json.str('expire'),
        nsset: json.str('nsset'),
        ourRegistrar: json.str('our_registrar'),
        raw: json.str('raw'),
      );
}

class StaffDomainStats {
  const StaffDomainStats({
    required this.total,
    required this.active,
    required this.pending,
    required this.expired,
    required this.expiringSoon,
    required this.autoRenew,
    this.cancelled = 0,
    this.failed = 0,
    this.ours = 0,
    this.external = 0,
    this.ourRegistrar,
  });

  final int total;
  final int active;
  final int pending;
  final int expired;
  final int expiringSoon;
  final int autoRenew;
  final int cancelled;
  final int failed;

  /// Live domains the registry confirms are sponsored by [ourRegistrar].
  final int ours;

  /// Live domains sponsored elsewhere, or not yet confirmed by a sync.
  final int external;

  /// The platform's registrar handle at the registry, e.g. `REG-MOINFOTECH`.
  final String? ourRegistrar;

  factory StaffDomainStats.fromJson(Map<String, dynamic> json) =>
      StaffDomainStats(
        total: json.count('total'),
        active: json.count('active'),
        pending: json.count('pending'),
        expired: json.count('expired'),
        expiringSoon: json.count('expiring_soon'),
        autoRenew: json.count('auto_renew'),
        cancelled: json.count('cancelled'),
        failed: json.count('failed'),
        ours: json.count('ours'),
        external: json.count('external'),
        ourRegistrar: json.str('our_registrar'),
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

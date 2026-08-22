/// Operations models added with the Aug 2026 web sidebar: active sessions,
/// the tenant-wide portal user directory, and cPanel account discovery.
///
/// Shapes follow `SessionController`, `ClientPortalUserController::indexAll`
/// and `HostingAccountController::discover`.
library;

import '../json.dart';

// ---------------------------------------------------------------------------
// Active sessions
// ---------------------------------------------------------------------------

/// One Sanctum token. Tokens never expire on their own here, and deactivating
/// an account only blocks future logins — so this list is the only place a
/// stale or orphaned session can be seen and revoked.
class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.ownerName,
    required this.ownerActive,
    required this.effectivelyActive,
    required this.neverUsed,
    this.tokenName,
    this.ownerEmail,
    this.clientName,
    this.clientStatus,
    this.lastUsedAt,
    this.createdAt,
  });

  /// Integer primary key on `personal_access_tokens`, stringified.
  final String id;

  /// staff | client.
  final String ownerType;
  final String ownerId;
  final String ownerName;
  final bool ownerActive;

  /// False when the owner is deactivated, or (for clients) the client record
  /// itself is no longer active.
  final bool effectivelyActive;
  final bool neverUsed;
  final String? tokenName;
  final String? ownerEmail;
  final String? clientName;
  final String? clientStatus;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;

  bool get isStaff => ownerType == 'staff';

  factory ActiveSession.fromJson(Map<String, dynamic> json) => ActiveSession(
        id: json.id(),
        ownerType: json.strOr('owner_type', 'staff'),
        ownerId: json.id('owner_id'),
        ownerName: json.strOr('owner_name', '—'),
        ownerActive: json.flag('owner_active', fallback: true),
        effectivelyActive: json.flag('effectively_active', fallback: true),
        neverUsed: json.flag('never_used'),
        tokenName: json.str('token_name'),
        ownerEmail: json.str('owner_email'),
        clientName: json.str('client_name'),
        clientStatus: json.str('client_status'),
        lastUsedAt: json.date('last_used_at'),
        createdAt: json.date('created_at'),
      );
}

class SessionsSummary {
  const SessionsSummary({
    required this.total,
    required this.neverUsed,
    required this.onInactive,
  });

  final int total;
  final int neverUsed;

  /// Sessions whose owner is deactivated — the ones bulk-revoke removes.
  final int onInactive;

  factory SessionsSummary.fromJson(Map<String, dynamic> json) =>
      SessionsSummary(
        total: json.count('total'),
        neverUsed: json.count('never_used'),
        onInactive: json.count('on_inactive'),
      );
}

class SessionsPage {
  const SessionsPage({required this.sessions, required this.summary});

  final List<ActiveSession> sessions;

  /// Counts for the UNFILTERED set — the controller computes them before
  /// applying the list filters.
  final SessionsSummary summary;

  factory SessionsPage.fromJson(Map<String, dynamic> json) => SessionsPage(
        sessions: json.list('data', ActiveSession.fromJson),
        summary: SessionsSummary.fromJson(json.object('summary') ?? const {}),
      );
}

// ---------------------------------------------------------------------------
// Portal user directory
// ---------------------------------------------------------------------------

/// A client's portal login, as listed tenant-wide by `GET /portal-users`.
class PortalUserRow {
  const PortalUserRow({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    required this.clientId,
    required this.clientName,
    this.phone,
    this.lastLoginAt,
  });

  final String id;
  final String name;
  final String email;

  /// admin | viewer.
  final String role;
  final bool isActive;
  final String clientId;
  final String clientName;
  final String? phone;
  final DateTime? lastLoginAt;

  factory PortalUserRow.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    return PortalUserRow(
      id: json.id(),
      name: json.strOr('name', '—'),
      email: json.strOr('email', ''),
      role: json.strOr('role', 'viewer'),
      isActive: json.flag('is_active', fallback: true),
      clientId: client?.id() ?? json.id('client_id'),
      clientName: client?.strOr('name', '—') ?? '—',
      phone: json.str('phone'),
      lastLoginAt: json.date('last_login_at'),
    );
  }
}

// ---------------------------------------------------------------------------
// cPanel account discovery
// ---------------------------------------------------------------------------

/// A WHM server configured for this tenant (`GET /servers`).
class HostingServer {
  const HostingServer({
    required this.id,
    required this.name,
    required this.isActive,
    required this.hostingAccountsCount,
    this.hostname,
  });

  final String id;
  final String name;
  final bool isActive;
  final int hostingAccountsCount;
  final String? hostname;

  factory HostingServer.fromJson(Map<String, dynamic> json) => HostingServer(
        id: json.id(),
        name: json.strOr('name', '—'),
        isActive: json.flag('is_active', fallback: true),
        hostingAccountsCount: json.count('hosting_accounts_count'),
        hostname: json.str('hostname'),
      );
}

/// One cPanel account as WHM reports it, merged with whether MoBilling
/// already tracks it. Un-imported accounts are sites being hosted — and
/// possibly never billed — that no client here is linked to.
class DiscoveredAccount {
  const DiscoveredAccount({
    required this.serverId,
    required this.serverName,
    required this.cpanelUsername,
    required this.suspended,
    required this.imported,
    this.domain,
    this.email,
    this.plan,
    this.diskUsed,
    this.diskLimit,
    this.hostingAccountId,
    this.clientId,
    this.clientName,
  });

  final String serverId;
  final String serverName;
  final String cpanelUsername;
  final bool suspended;
  final bool imported;
  final String? domain;
  final String? email;
  final String? plan;

  /// WHM strings like `512M` — shown verbatim.
  final String? diskUsed;
  final String? diskLimit;
  final String? hostingAccountId;
  final String? clientId;
  final String? clientName;

  factory DiscoveredAccount.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    return DiscoveredAccount(
      serverId: json.id('server_id'),
      serverName: json.strOr('server_name', '—'),
      cpanelUsername: json.strOr('cpanel_username', '—'),
      suspended: json.flag('suspended'),
      imported: json.flag('imported'),
      domain: json.str('domain'),
      email: json.str('email'),
      plan: json.str('plan'),
      diskUsed: json.str('disk_used'),
      diskLimit: json.str('disk_limit'),
      hostingAccountId: json.str('hosting_account_id'),
      clientId: client?.id(),
      clientName: client?.str('name'),
    );
  }
}

/// `GET /hosting-accounts/discover` — rows plus per-server errors (a server
/// that could not be reached contributes an error, not an exception, so the
/// others still list).
class DiscoveryResult {
  const DiscoveryResult({required this.accounts, required this.errors});

  final List<DiscoveredAccount> accounts;
  final List<String> errors;

  int get unimportedCount => accounts.where((a) => !a.imported).length;

  factory DiscoveryResult.fromJson(Map<String, dynamic> json) =>
      DiscoveryResult(
        accounts: json.list('data', DiscoveredAccount.fromJson),
        errors: json.strings('errors'),
      );
}

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/admin_menu.dart';
import '../../navigation/shell.dart';

/// Routes a tapped push notification to the screen it's about.
///
/// Every notification class in the backend now pushes (see PUSH_SETUP.md),
/// spanning all three shells — so unlike the first cut of this file, a
/// `type` can no longer be assumed portal-only. [currentShell] resolves the
/// ambiguous ones (today: `ticket`, sent to both a portal client and staff).
///
/// Full coverage as of the second sweep — every `data.type` PUSH_SETUP.md
/// lists now either resolves to a real route or is a deliberate no-op
/// (`message`, `broadcast`, `otp_requested`, `password_reset_requested` carry
/// no id/link by design — informational only, and two of those never carry
/// the secret they're about). Several staff-facing types (`bill`,
/// `leave_request`, `staff_report`, `staff_target`, `system_verification`,
/// `verification_reminder`, `satisfaction_call`) land on their list screen
/// rather than a specific row — no per-item detail route exists yet for any
/// of them, so the list is the honest ceiling today.
void wirePushDeepLinks(GoRouter router, AppShell Function() currentShell) {
  void handle(RemoteMessage message) {
    final path = _pathFor(message.data, currentShell());
    if (path != null) router.push(path);
  }

  // Tapped while backgrounded.
  FirebaseMessaging.onMessageOpenedApp.listen(handle);
  // Tapped while terminated — the tap is what launched the app, so there's
  // no "opened" event to listen for; the message is handed back instead.
  FirebaseMessaging.instance.getInitialMessage().then((message) {
    if (message != null) handle(message);
  });
}

String? _pathFor(Map<String, dynamic> data, AppShell shell) {
  switch (data['type']) {
    // InvoiceSentNotification and its whole family (cancelled, overdue,
    // termination warning, recurring/bundled reminders) all target a
    // portal Client — never staff — so this stays unconditional.
    // BundledReminderNotification carries only a count, no document —
    // genuinely un-routable, so the null id case is expected here.
    case 'invoice':
    case 'payment':
      final id = data['document_id'];
      return id == null ? null : '/portal/invoices/$id';
    // TicketRepliedNotification targets the portal client who filed the
    // ticket; TicketActivityStaffNotification targets the staff member
    // it's assigned to. Same `type`, different owner, different route.
    case 'ticket':
      final id = data['ticket_id'];
      if (id == null) return null;
      return shell == AppShell.portal ? '/portal/tickets/$id' : '/tickets/$id';
    // Staff-facing: a bill's own detail row, if a future screen adds one —
    // the list is what exists today.
    case 'bill':
      return '/bills';
    // DocumentSentConfirmation — staff, not portal (they just sent it).
    // OrderPlacedNotification — staff; a client's self-service order, with
    // the new invoice it generated.
    case 'document':
    case 'order':
      final id = data['document_id'];
      return id == null ? null : '/documents/$id';
    // PaymentReceivedNotification — staff; an online gateway payment landed
    // with no staff involved. Routes to the invoice it paid, same as
    // 'order' above — there is no standalone payments-list route, only the
    // "Payments" bottom tab, which isn't reachable by path.
    case 'payment_received':
      final id = data['document_id'];
      return id == null ? null : '/documents/$id';
    // HostingUpgradeRequestedNotification — staff; a client changed their
    // own plan. No per-account detail route exists on the staff side yet.
    case 'hosting_upgrade':
      return '/hosting';
    // DomainRenewalRequestedNotification — staff; same reasoning, no
    // per-domain detail route on the staff side yet.
    case 'domain_renewal':
      return '/domains';
    // CronJobFailedNotification — platform super admin; these commands run
    // tenant-wide in one pass, so this is never staff's problem. No
    // dedicated cross-tenant cron-log screen exists yet, so this lands on
    // the console itself rather than nowhere.
    case 'cron_failure':
      return AdminRoutes.home;
    // DomainRegistered/Renewed/ExpiryReminder/AuthInfoRevealed — portal.
    case 'domain':
    // SslExpiryReminder — portal; SSL is shown on the domain's own detail
    // screen, there is no separate SSL screen to link to.
    case 'ssl':
      final id = data['domain_id'];
      return id == null ? null : '/portal/domains/$id';
    // HostingAccountProvisioned/StatusChanged/PasswordChanged — portal.
    case 'hosting':
      final id = data['hosting_account_id'];
      return id == null ? null : '/portal/hosting/$id';
    // LeaveRequestSubmitted/Decided — staff.
    case 'leave_request':
      return '/leave';
    // StaffReportSubmitted/Reviewed/Reply/DeadlineReminder — staff. The
    // deadline reminder carries no id at all; the other three have one but
    // no `/staff-reports/:id` route exists yet either way.
    case 'staff_report':
      return '/staff-reports';
    // StaffTargetAssigned and all 5 supervisor/manager/self-report/verified
    // variants — staff.
    case 'staff_target':
      return '/staff-targets';
    // NewTenantNotification — platform super admin.
    case 'new_tenant':
      final id = data['tenant_id'];
      return id == null ? null : AdminRoutes.tenantPath(id.toString());
    // SmsActivationRequestNotification — platform super admin. The FCM
    // payload's `tenant_id` is used directly rather than the stored
    // notification's web-only `?tenant=` query-string URL.
    case 'sms_activation':
      final id = data['tenant_id'];
      return id == null ? null : AdminRoutes.tenantSmsPath(id.toString());
    // SystemVerificationIssueNotification — staff.
    case 'system_verification':
      return '/system-verifications';
    // VerificationReminderNotification — staff, "my checks due" list.
    case 'verification_reminder':
      return '/my-verifications';
    // SatisfactionCallDailyReminderNotification — staff.
    case 'satisfaction_call':
      return '/satisfaction-calls';
    // WelcomeNotification — the stored copy's `url` is the web path
    // `/dashboard`, which doesn't exist here; the mobile landing tab is
    // `/home`.
    case 'welcome':
      return '/home';
    // SmsLowBalanceNotification / SmsPurchaseFailedNotification — staff.
    case 'sms_low_balance':
    case 'sms_purchase_failed':
      return '/sms';
    // ImpersonationUsedNotification — staff (the tenant's other admins).
    case 'impersonation_used':
      return '/team';
    // ClientMessage/BroadcastNotification (portal, no id ever included) and
    // PortalOtp/ResetPassword (security: deliberately carry no code/token,
    // staff or portal depending on which) are intentional no-ops — nothing
    // to navigate to.
    default:
      return null;
  }
}

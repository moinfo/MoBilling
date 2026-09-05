# Push notifications

## Status

- **Backend**: fully live, on every notification. `POST/DELETE /device-tokens`
  (any signed-in user — staff, super admin, or portal) and
  `/portal/device-tokens` (same controller, kept for the portal-prefixed
  path) register/unregister a device's FCM token. `FcmService` sends via the
  FCM HTTP v1 API using a real service-account credential (`FCM_CREDENTIALS`
  is set; verified end-to-end with a live send that authenticated correctly
  and was only rejected for using a fake token), and prunes tokens FCM
  reports as UNREGISTERED. **Every one of the app's 53 notification classes**
  now pushes — see the table below — spanning portal clients, tenant staff,
  and platform super admins.
- **5 new business-event notifications** (2026-09), closing gaps a user
  flagged directly — a client placing a hosting/domain order fired NOTHING to
  staff before this, and 4 similar silent spots: `OrderPlacedNotification`
  (`PortalOrderController::store`, `PortalDomainController::order` — only
  when a client orders for themselves, not staff ordering on their behalf),
  `PaymentReceivedNotification` (`TenantPesapalWebhookController` only — an
  online gateway payment with zero staff involvement; a staff-recorded
  `PaymentInController::store` payment isn't news to the staff member who
  just typed it in), `HostingUpgradeRequestedNotification`
  (`PortalHostingController::upgrade`, both the free-immediate and the
  paid-prorated-invoice branches), `DomainRenewalRequestedNotification`
  (`PortalDomainController::renew`), and `CronJobFailedNotification` (a
  `CronLog` model `created` event, not a per-command dispatch call — these
  scheduled commands run tenant-wide in one pass with `tenant_id: null`, so a
  failure is a platform problem and goes to super admins, not tenant staff).
  Recipients are resolved by a new `User::withPermission($tenantId,
  $permission)` helper (`orders.create`, `payments_in.read`,
  `hosting.change_package`, `domains.renew` respectively) — the same
  permission-based query `TicketController::staffToNotify` already used ad
  hoc, pulled out so these 4 new call sites (and future ones) share it.
- **3 more (medium priority)**: `SmsLowBalanceNotification`
  (`SmsPurchaseController::balance()`, throttled to once per tenant per day
  via `Cache::add` so a polled dashboard widget can't spam it — threshold is
  `LOW_BALANCE_THRESHOLD = 50`), `SmsPurchaseFailedNotification`
  (`checkout()`'s Pesapal-submission catch block), and
  `ImpersonationUsedNotification` (`UserController::impersonate` — audit
  visibility for the tenant's OTHER `settings.users` holders when one staff
  member signs in as another; neither the actor nor the impersonated account
  is notified). All three via `User::withPermission`/`withPermission`-style
  filtering, same pattern as the 5 above.
- **Android app** (`apps/staff`): live. Firebase is initialized in `main.dart`,
  `FirebasePushRegistration` (in `lib/features/push/push_registration.dart`)
  requests permission, registers the FCM token, and re-registers on
  `onTokenRefresh`. `SessionController` calls it after every login,
  registration, impersonation swap, and app-relaunch session restore, and
  unregisters the token right before a token is revoked at sign-out.
- **Tap-to-deep-link**: complete. `lib/features/push/push_deep_link.dart`'s
  `_pathFor` now covers every `data.type` in the table below. Most staff-facing
  types (`bill`, `leave_request`, `staff_report`, `staff_target`,
  `system_verification`, `verification_reminder`, `satisfaction_call`) land on
  their list screen rather than one specific row, since no per-item detail
  route exists yet for any of them — that's the honest ceiling today, not an
  oversight. `message`/`broadcast`/`otp_requested`/`password_reset_requested`
  are deliberate no-ops: none of the four ever carries an id or link (the last
  two by design, so a push never contains a live code/token).
- **In-app notification centre**: live, staff shell only (mirrors web's bell,
  which is likewise absent from the portal). `GET /notifications`,
  `/notifications/unread-count`, `PATCH /notifications/{id}/read`,
  `POST /notifications/mark-all-read` — plain Laravel `Notifiable`, no
  customisation. Only the notification classes whose `via()` includes
  `'database'` ever appear here (30 of 53 as of the latest additions — the
  rest are push/mail/sms only, mostly portal-client-targeted). `NotificationsScreen` (`/notifications`), reachable
  from a bell badge on the dashboard tab's masthead
  (`features/notifications/notification_bell.dart`) next to the account
  avatar — this app has no single chrome layer every masthead shares, so the
  bell lives on the one screen every session always has rather than being
  duplicated per screen. One confirmed backend inconsistency, worked around
  client-side: `TicketActivityStaffNotification`'s stored payload uses `link`
  instead of `url`, and carries no `type` or ticket id at all — `AppNotification.target`
  reads `url ?? link`, but tapping that one can only reach the ticket list, not
  the specific ticket (web's own bell has the identical limitation).
- **Foreground display**: not implemented. Android doesn't surface FCM's
  `notification` payload as a system notification while the app is
  foregrounded — that needs a local-notifications package, which hasn't been
  added. The unread-count badge polls every 30s regardless (matching web), so
  an open session still finds out, just without a banner.
- **iOS app**: not started. `firebase_options.dart` only has an `android`
  entry — `DefaultFirebaseOptions.currentPlatform` throws on iOS on purpose,
  so `main.dart` skips Firebase entirely there and the session falls back to
  `NoopPushRegistration`.

## Remaining: iOS

1. Firebase console → add an iOS app (bundle `tz.co.mobilling.staff`),
   download `GoogleService-Info.plist` into `apps/staff/ios/Runner/`.
2. Xcode → Runner → Signing & Capabilities → **+ Capability** → Push
   Notifications, and upload an APNs key to the Firebase project.
3. `flutterfire configure` (or hand-add an `ios` entry to
   `DefaultFirebaseOptions` the same way `android` was added) so
   `currentPlatform` resolves there too.
4. Drop the `defaultTargetPlatform == TargetPlatform.android` guard in
   `main.dart` and the `Platform.isAndroid` check in
   `providers.dart#pushRegistrationProvider` once both platforms are covered.

## What gets pushed

Every notification in `app/Notifications/` pushes now. Grouped by `data.type`:

| type | Notifications | Recipient |
|---|---|---|
| `invoice` | InvoiceSent, InvoiceCancelled, InvoiceOverdueReminder, InvoiceLateFee, InvoiceTerminationWarning, RecurringInvoiceReminder, BundledReminder | portal client |
| `payment` | PaymentReceipt | portal client |
| `order` | OrderPlaced | staff (`orders.create`) |
| `payment_received` | PaymentReceived | staff (`payments_in.read`) — online gateway payments only |
| `hosting_upgrade` | HostingUpgradeRequested | staff (`hosting.change_package`) |
| `domain_renewal` | DomainRenewalRequested | staff (`domains.renew`) |
| `cron_failure` | CronJobFailed | super admin — tenant-wide commands, not tenant staff |
| `sms_low_balance` | SmsLowBalance | staff (`menu.sms`) — throttled to once/day per tenant |
| `sms_purchase_failed` | SmsPurchaseFailed | staff (`menu.sms`) |
| `impersonation_used` | ImpersonationUsed | staff — the tenant's other `settings.users` holders |
| `ticket` | TicketReplied (client) / TicketActivityStaff (staff) | both — shell-resolved |
| `bill` | BillDueReminder, BillOverdue | staff |
| `document` | DocumentSentConfirmation | staff |
| `domain` | DomainRegistered, DomainRenewed, DomainExpiryReminder, DomainAuthInfoRevealed | portal client |
| `hosting` | HostingAccountProvisioned, HostingStatusChanged, HostingPasswordChanged | portal client |
| `subscription` | SubscriptionReactivated, SubscriptionSuspended | portal client |
| `ssl` | SslExpiryReminder | portal client |
| `message` | ClientMessage | portal client |
| `broadcast` | Broadcast | portal client |
| `leave_request` | LeaveRequestSubmitted, LeaveRequestDecided | staff |
| `staff_report` | StaffReportSubmitted/Reviewed/Reply/DeadlineReminder | staff |
| `staff_target` | StaffTargetAssigned (+supervisor/manager variants), SelfReported, Verified (+manager) | staff |
| `new_tenant` | NewTenant | super admin |
| `sms_activation` | SmsActivationRequest | admin |
| `system_verification` | SystemVerificationIssue | admin |
| `verification_reminder` | VerificationReminder | staff |
| `satisfaction_call` | SatisfactionCallDailyReminder | staff |
| `welcome` | Welcome | new tenant admin |
| `otp_requested` | PortalOtp | portal — **body never contains the code itself** |
| `password_reset_requested` | ResetPassword | staff — **body never contains the token/link** |

`DomainAuthInfoRevealedNotification` and `HostingPasswordChangedNotification`
follow the same rule: the push alerts that a secret (EPP code / hosting
password) was revealed or changed, never carries the secret.

Foreground display isn't implemented (Android doesn't surface FCM's
`notification` payload as a system notification while the app is
foregrounded; that needs a local-notifications package, which hasn't been
added) — background/terminated taps work today.

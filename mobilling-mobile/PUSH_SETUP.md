# Push notifications

## Status

- **Backend**: fully live, on every notification. `POST/DELETE /device-tokens`
  (any signed-in user — staff, super admin, or portal) and
  `/portal/device-tokens` (same controller, kept for the portal-prefixed
  path) register/unregister a device's FCM token. `FcmService` sends via the
  FCM HTTP v1 API using a real service-account credential (`FCM_CREDENTIALS`
  is set; verified end-to-end with a live send that authenticated correctly
  and was only rejected for using a fake token), and prunes tokens FCM
  reports as UNREGISTERED. **Every one of the app's 45 notification classes**
  now pushes — see the table below — spanning portal clients, tenant staff,
  and platform super admins.
- **Android app** (`apps/staff`): live. Firebase is initialized in `main.dart`,
  `FirebasePushRegistration` (in `lib/features/push/push_registration.dart`)
  requests permission, registers the FCM token, and re-registers on
  `onTokenRefresh`. `SessionController` calls it after every login,
  registration, impersonation swap, and app-relaunch session restore, and
  unregisters the token right before a token is revoked at sign-out.
- **Tap-to-deep-link**: partial. `lib/features/push/push_deep_link.dart`
  handles `invoice`/`payment` (always portal) and `ticket` (portal or staff,
  resolved from the signed-in shell — `TicketRepliedNotification` targets a
  client, `TicketActivityStaffNotification` targets staff, and both use the
  same `type`). The ~20 other `type` values introduced in the sweep below
  (`bill`, `domain`, `hosting`, `subscription`, `ssl`, `staff_report`,
  `staff_target`, `leave_request`, `broadcast`, `new_tenant`, …) aren't mapped
  to a route yet — tapping one of those today just opens the app with no
  navigation (safe no-op, not a crash). Extend `_pathFor` in that file per
  type, as screens are confirmed to exist for each.
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

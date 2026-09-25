# Hosting: bandwidth-suspended upgrade ("upgrade now, pay later")

Accounts suspended ONLY because they reached their bandwidth limit (`HostingAccount::suspensionReason() === 'bandwidth'`)
can upgrade themselves from the portal (admin role) or WhatsApp. Active accounts and billing/other suspensions keep the
classic **pay first** flow (invoice due today; the plan is applied by `DocumentObserver` when it is paid).

## Flow (bandwidth-suspended + eligible)

1. Client picks a higher plan and confirms ("Upgrade now — pay within 3 days").
2. `PayLaterUpgradeService::apply()` in ONE transaction: creates the prorated invoice (status `sent`, due today + 3 days,
   note "Upgrade — pay within 3 days"), stores the marker `subscription.metadata.pay_later_upgrade`
   (`document_id, previous_product_service_id, previous_cpanel_package, previous_recurring_amount, applied_at, due_date`),
   then runs the SAME apply path as a paid upgrade (`PlanChangeService::apply` -> WHM changepackage -> showbw refresh ->
   unsuspend when new limit > usage). If WHM did not switch the package, everything is rolled back and the client falls back to pay-first.
3. When the invoice is paid, `DocumentObserver` -> `onPaid()` only clears the marker (the plan is NEVER applied a second time).
4. Provisioning log actions: `pay_later_upgrade_applied`, `pay_later_upgrade_paid`, `pay_later_upgrade_reverted`.
   Staff (`hosting.change_package`) get "Upgrade applied before payment"; the existing bandwidth notification also mentions
   "Upgrade pending payment (due <date>)".

## Guards (any failure -> pay-first with an explanation)

| Guard | Value |
|---|---|
| Portal role | admin only (WhatsApp: the verified client) |
| Other invoices | none overdue by more than 7 days (`hosting.pay_later_upgrade_overdue_days`) |
| Open pay-later upgrade | none pending for the account |
| Frequency | max one per account per 60 days (`hosting.pay_later_upgrade_cooldown_days`) |
| Amount | invoice total <= `hosting.pay_later_upgrade_max` (env `HOSTING_PAY_LATER_UPGRADE_MAX`, default TZS 500,000) |
| Bandwidth | refused when the plan's KNOWN limit (WHM listpkgs) is <= current usage; unknown limit is allowed |
| Plan | must be a higher-priced plan with a different cPanel package |

Config: `config/hosting.php` (`pay_later_upgrade_max`, `_due_days` 3, `_cooldown_days` 60, `_overdue_days` 7,
`_staff_alert_after_days` 2). The portal API accepts `mode=pay_first` to skip pay-later explicitly.

## Non-payment: `php artisan hosting:review-pay-later-upgrades [--dry-run]` (daily 09:15)

* Due day .. due+2: one reminder per day to the client (existing invoice notifications; idempotent via `reminded_days`).
* More than 2 days past due: ONE staff notification ("Upgrade still unpaid after the due date").
* **Nothing is reverted or re-suspended automatically.** Staff can use "Revert pay-later upgrade" on the service page
  (`POST /hosting-services/{id}/revert-pay-later-upgrade`, permission `client_subscriptions.update`): restores the previous
  plan through the same apply path (no downgrade credit), cancels the unpaid invoice, leaves the account state for staff.
  Refused when the invoice is already (partly) paid.
* Note: `invoices:process-overdue` (late fees, 7/14-day dunning) still applies to this invoice like any other.

Staff visibility: the service selector and the service page show "Upgrade pending payment (due <date>)".
The manual "Fix Bandwidth Suspension" staff action is unchanged.

Tests: `php tests/Manual/run_hosting_pay_later_upgrade.php` (fake WHM, rolled back) and `run_hosting_bandwidth_upgrade.php`.

<?php

namespace App\Services\Hosting;

use App\Models\ClientSubscription;
use App\Models\Document;
use App\Models\HostingAccount;
use App\Models\ProductService;
use App\Models\ProvisioningLog;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\HostingPayLaterUpgradeNotification;
use App\Notifications\InvoiceOverdueReminderNotification;
use App\Notifications\InvoiceSentNotification;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Notification;

/**
 * "Upgrade now, pay later" for BANDWIDTH-suspended hosting: the plan is switched and the account restored
 * immediately, the prorated invoice is due a few days later. Everything (guards, apply, paid, review, revert)
 * lives here. The marker is subscription metadata `pay_later_upgrade`:
 *   {status:'pending', document_id, previous_product_service_id, previous_cpanel_package,
 *    previous_recurring_amount, applied_at, due_date, reminded_days:[], staff_alerted_at}
 * Nothing here ever reverts a plan or re-suspends an account on its own; reverting is a staff action.
 */
class PayLaterUpgradeService
{
    public function __construct(private BandwidthSuspensionService $bw, private PlanChangeService $plans) {}

    public function pending(?ClientSubscription $sub): ?array
    {
        $m = $sub?->metadata['pay_later_upgrade'] ?? null;
        return is_array($m) && ($m['status'] ?? null) === 'pending' ? $m : null;
    }

    /** Invoice total (charge + tax) the client would owe for switching to $new. */
    public function invoiceTotal(ProductService $new, float $charge): float
    {
        return round($charge + round($charge * (float) ($new->tax_percent ?? 0) / 100, 2), 2);
    }

    public function dueDate(): string
    {
        return now()->addDays((int) config('hosting.pay_later_upgrade_due_days', 3))->toDateString();
    }

    /**
     * Account/client-level guards (independent of the chosen plan). null = eligible, else the reason.
     */
    public function accountRefusal(HostingAccount $account, ClientSubscription $sub): ?string
    {
        if (!$this->bw->isBandwidthSuspended($account)) {
            return 'Pay-later is only for accounts suspended for bandwidth.';
        }
        if ($this->pending($sub)) {
            return 'An earlier upgrade on this account is still waiting for payment.';
        }
        $days = (int) config('hosting.pay_later_upgrade_cooldown_days', 60);
        $last = $sub->metadata['pay_later_last_applied_at'] ?? null;
        if ($last && Carbon::parse($last)->greaterThan(now()->subDays($days))) {
            return "Only one pay-later upgrade is allowed every {$days} days.";
        }
        $overdueDays = (int) config('hosting.pay_later_upgrade_overdue_days', 7);
        $overdue = Document::withoutGlobalScopes()
            ->where('tenant_id', $sub->tenant_id)->where('client_id', $sub->client_id)->where('type', 'invoice')
            ->whereNotIn('status', ['paid', 'draft', 'pending_approval', 'cancelled'])
            ->whereNotNull('due_date')
            ->where('due_date', '<', now()->startOfDay()->subDays($overdueDays)->toDateString())
            ->exists();
        if ($overdue) {
            return 'You have an invoice that is more than ' . $overdueDays . ' days overdue.';
        }

        return null;
    }

    /** Plan-level guards. null = eligible. */
    public function planRefusal(HostingAccount $account, ClientSubscription $sub, ProductService $new, float $charge): ?string
    {
        if ($charge <= 0 || $this->plans->direction($sub, $new) !== 'upgrade') {
            return 'Only a higher plan can be upgraded before payment.';
        }
        if ($new->provisioning_type !== 'whm_cpanel' || !$new->cpanel_package || $account->package === $new->cpanel_package) {
            return 'This plan cannot be applied automatically.';
        }
        $known = $this->bw->planLimitBytes($new, $account->server);
        if ($known !== null && $known <= (float) ($account->meta['bw_used_bytes'] ?? 0)) {
            return 'That plan\'s bandwidth allowance is still below your current usage.';
        }
        $cap = (float) config('hosting.pay_later_upgrade_max', 500000);
        if ($this->invoiceTotal($new, $charge) > $cap) {
            return 'The upgrade amount is above the limit for upgrading before payment.';
        }

        return null;
    }

    public function refusal(HostingAccount $account, ClientSubscription $sub, ProductService $new, float $charge): ?string
    {
        return $this->accountRefusal($account, $sub) ?? $this->planRefusal($account, $sub, $new, $charge);
    }

    /**
     * Invoice + marker + plan change + reactivation, all before payment. Throws \DomainException with a
     * client-safe message when a guard refuses (caller falls back to pay-first) or WHM did not apply the package
     * (everything is rolled back, the account is untouched).
     *
     * @return array{document: Document, restored: bool, account_status: string, due_date: string}
     */
    public function apply(ClientSubscription $sub, HostingAccount $account, ProductService $new): array
    {
        $days = (int) config('hosting.pay_later_upgrade_due_days', 3);

        $result = DB::transaction(function () use ($sub, $account, $new, $days) {
            $sub = ClientSubscription::withoutGlobalScopes()->with('productService')->lockForUpdate()->findOrFail($sub->id);
            $account = HostingAccount::withoutGlobalScopes()->with('server')->findOrFail($account->id);
            $charge = $this->plans->proratedCharge($sub, $new);
            if ($msg = $this->refusal($account, $sub, $new, $charge)) {
                throw new \DomainException($msg);
            }

            $previous = [
                'previous_product_service_id' => $sub->product_service_id,
                'previous_cpanel_package'     => $account->package,
                'previous_recurring_amount'   => $sub->recurring_amount,
            ];
            $document = $this->plans->createUpgradeInvoice($sub, $new, $charge, $account->domain, $days, false, "Upgrade — pay within {$days} days");
            $due = $document->due_date->toDateString();

            $meta = $sub->metadata ?? [];
            $meta['pay_later_upgrade'] = $previous + [
                'status' => 'pending', 'document_id' => $document->id, 'applied_at' => now()->toIso8601String(),
                'due_date' => $due, 'reminded_days' => [], 'staff_alerted_at' => null,
            ];
            $meta['pay_later_last_applied_at'] = now()->toIso8601String();
            $sub->update(['metadata' => $meta]);

            // The SAME apply path as a paid upgrade: changepackage -> showbw refresh -> reactivate when new limit > usage.
            $this->plans->apply($sub, $new, true);

            $fresh = $account->fresh();
            if ($fresh->package !== $new->cpanel_package) {
                throw new \DomainException('The upgrade could not be applied right now. Please pay the invoice first, or contact support.');
            }

            return [$document, $fresh, $due, $previous];
        });

        [$document, $fresh, $due, $previous] = $result;
        $restored = $fresh->status === 'active';
        $this->log($fresh, 'pay_later_upgrade_applied', true, [
            'document_id' => $document->id, 'due_date' => $due, 'total' => (float) $document->total,
            'to_product_service_id' => $new->id, 'restored' => $restored,
        ] + $previous);
        $this->notifyStaff($fresh, 'applied', $document, $due, $sub->client?->name);

        return ['document' => $document, 'restored' => $restored, 'account_status' => $fresh->status, 'due_date' => $due];
    }

    /** The pay-later invoice was paid: clear the pending marker (plan is already applied — never applied twice). */
    public function onPaid(ClientSubscription $sub, Document $document): void
    {
        $m = $this->pending($sub);
        if (!$m || ($m['document_id'] ?? null) !== $document->id) {
            return;
        }
        $meta = $sub->metadata ?? [];
        unset($meta['pay_later_upgrade']);
        $meta['pay_later_last_paid_at'] = now()->toIso8601String();
        $sub->update(['metadata' => $meta]);

        if ($account = $this->accountFor($sub)) {
            $this->log($account, 'pay_later_upgrade_paid', true, ['document_id' => $document->id]);
        }
    }

    /** Staff action: restore the previous plan through the normal apply path. Account state is left for staff. */
    public function revert(ClientSubscription $sub): void
    {
        $document = DB::transaction(function () use ($sub) {
            $sub = ClientSubscription::withoutGlobalScopes()->lockForUpdate()->findOrFail($sub->id);
            $m = $this->pending($sub);
            if (!$m) {
                throw new \DomainException('This service has no pay-later upgrade waiting for payment.');
            }
            $document = Document::withoutGlobalScopes()->where('tenant_id', $sub->tenant_id)->find($m['document_id'] ?? null);
            if ($document && in_array($document->status, ['paid', 'partial'], true)) {
                throw new \DomainException('The upgrade invoice is already (partly) paid — handle it manually.');
            }
            $previous = ProductService::withoutGlobalScopes()->where('tenant_id', $sub->tenant_id)->find($m['previous_product_service_id'] ?? null);
            if (!$previous) {
                throw new \DomainException('The previous plan no longer exists.');
            }

            $document?->update(['status' => 'cancelled']);
            $meta = $sub->metadata ?? [];
            unset($meta['pay_later_upgrade']);
            $meta['pay_later_reverted_at'] = now()->toIso8601String();
            $sub->update(['metadata' => $meta]);

            $this->plans->apply($sub->load('productService'), $previous, true);
            $sub->refresh()->update(['recurring_amount' => $m['previous_recurring_amount'] ?? null]);

            return $document;
        });

        if ($account = $this->accountFor($sub->fresh())) {
            $this->log($account, 'pay_later_upgrade_reverted', true, ['document_id' => $document?->id, 'by_user_id' => auth()->id()]);
            $this->notifyStaff($account, 'reverted', $document, null, $sub->client?->name);
        }
    }

    /**
     * Daily review. Returns counts. Reminders to the client on due day .. +2, one staff alert after that.
     * Never reverts or suspends anything.
     *
     * @return array{reminders:int, staff_alerts:int, cleared:int}
     */
    public function review(bool $dryRun = false): array
    {
        $out = ['reminders' => 0, 'staff_alerts' => 0, 'cleared' => 0];
        $alertAfter = (int) config('hosting.pay_later_upgrade_staff_alert_after_days', 2);
        $today = Carbon::today();

        $subs = ClientSubscription::withoutGlobalScopes()->whereNotNull('metadata->pay_later_upgrade')->get();
        foreach ($subs as $sub) {
            $m = $this->pending($sub);
            if (!$m) {
                continue;
            }
            $document = Document::withoutGlobalScopes()->with('client')->find($m['document_id'] ?? null);
            if (!$document || $document->status === 'cancelled' || $document->status === 'paid') {
                if (!$dryRun) {
                    $document && $document->status === 'paid' ? $this->onPaid($sub, $document) : $this->clearMarker($sub);
                }
                $out['cleared']++;
                continue;
            }
            $tenant = Tenant::find($sub->tenant_id);
            $client = $document->client;
            $due = Carbon::parse($m['due_date'])->startOfDay();
            $daysOver = (int) $due->diffInDays($today, false);
            if ($daysOver < 0 || !$tenant || !$tenant->hasAccess()) {
                continue;
            }

            if ($daysOver <= $alertAfter) {
                $sent = $m['reminded_days'] ?? [];
                if (!in_array($daysOver, $sent, true)) {
                    $out['reminders']++;
                    if (!$dryRun && $client) {
                        try {
                            $client->notify($daysOver === 0
                                ? new InvoiceSentNotification($document)
                                : new InvoiceOverdueReminderNotification($document, $tenant, $daysOver));
                        } catch (\Throwable $e) {
                            Log::warning('Pay-later reminder failed', ['document_id' => $document->id, 'error' => $e->getMessage()]);
                        }
                        $this->patchMarker($sub, ['reminded_days' => array_merge($sent, [$daysOver])]);
                    }
                }
            } elseif (empty($m['staff_alerted_at'])) {
                $out['staff_alerts']++;
                if (!$dryRun && ($account = $this->accountFor($sub))) {
                    $this->notifyStaff($account, 'unpaid', $document, $m['due_date'], $client?->name);
                    $this->patchMarker($sub, ['staff_alerted_at' => now()->toIso8601String()]);
                }
            }
        }

        return $out;
    }

    private function patchMarker(ClientSubscription $sub, array $patch): void
    {
        $sub = ClientSubscription::withoutGlobalScopes()->find($sub->id);
        $meta = $sub->metadata ?? [];
        $meta['pay_later_upgrade'] = array_merge($meta['pay_later_upgrade'] ?? [], $patch);
        $sub->update(['metadata' => $meta]);
    }

    private function clearMarker(ClientSubscription $sub): void
    {
        $meta = $sub->metadata ?? [];
        unset($meta['pay_later_upgrade']);
        $sub->update(['metadata' => $meta]);
    }

    public function accountFor(ClientSubscription $sub): ?HostingAccount
    {
        return HostingAccount::withoutGlobalScopes()->where('client_subscription_id', $sub->id)->first()
            ?? HostingAccount::withoutGlobalScopes()->where('tenant_id', $sub->tenant_id)->where('domain', $sub->label)->first();
    }

    private function log(HostingAccount $account, string $action, bool $ok, array $request): void
    {
        try {
            ProvisioningLog::withoutGlobalScopes()->create([
                'tenant_id' => $account->tenant_id, 'hosting_account_id' => $account->id, 'server_id' => $account->server_id,
                'action' => $action, 'request' => $request, 'status' => $ok ? 'success' : 'failed',
            ]);
        } catch (\Throwable $e) {
            Log::warning('Pay-later upgrade log failed', ['hosting_account_id' => $account->id]);
        }
    }

    private function notifyStaff(HostingAccount $account, string $kind, ?Document $document, ?string $due, ?string $clientName): void
    {
        try {
            $staff = User::withPermission($account->tenant_id, 'hosting.change_package');
            if ($staff->isNotEmpty()) {
                Notification::send($staff, new HostingPayLaterUpgradeNotification($account, $kind, $document, $clientName, $due));
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }
}

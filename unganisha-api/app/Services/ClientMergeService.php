<?php

namespace App\Services;

use App\Models\Client;
use App\Models\ClientContact;
use App\Models\ClientCredit;
use App\Models\ClientDesignOrder;
use App\Models\ClientSubscription;
use App\Models\ClientUser;
use App\Models\CommunicationLog;
use App\Models\CouponRedemption;
use App\Models\Document;
use App\Models\Domain;
use App\Models\FieldVisit;
use App\Models\Followup;
use App\Models\PaymentIn;
use App\Models\RecurringInvoiceLog;
use App\Models\Refund;
use App\Models\SatisfactionCall;
use App\Models\SystemVerification;
use App\Models\Ticket;
use App\Models\WhatsappContact;
use Illuminate\Support\Facades\DB;

/**
 * Merge two client records: every table with a client_id FK gets its rows
 * re-pointed from the absorbed client onto the survivor, wallet balances
 * combine, and the absorbed client is retired (soft-deleted, not hard
 * deleted — mirrors DocumentController::merge()'s "mark as absorbed, never
 * hard-delete the originals" convention).
 *
 * Every table with a client_id column was enumerated by grepping all
 * migrations — keep this list in sync if a new one is added:
 * documents, client_subscriptions, communication_logs, followups,
 * satisfaction_calls, client_users, payments_in, whatsapp_contacts,
 * field_visits, client_design_orders, system_verifications, domains,
 * tickets, client_credits, refunds, coupon_redemptions, client_contacts,
 * recurring_invoice_logs (unique-constrained, handled specially).
 * `portal_otps` (transient, expiring, no model) and `broadcasts.client_ids`
 * (a JSON historical snapshot, not a live FK) are deliberately left alone.
 */
class ClientMergeService
{
    /** @return array<string,int> counts of rows moved per table, for the confirmation UI */
    public function merge(Client $survivor, Client $absorbed): array
    {
        if ($survivor->id === $absorbed->id) {
            throw new \InvalidArgumentException('Cannot merge a client into itself.');
        }

        return DB::transaction(function () use ($survivor, $absorbed) {
            // Lock both rows for the duration of the merge.
            $survivor = Client::withoutGlobalScopes()->whereKey($survivor->id)->lockForUpdate()->first();
            $absorbed = Client::withoutGlobalScopes()->whereKey($absorbed->id)->lockForUpdate()->first();

            $moved = [];

            $simpleMoves = [
                'documents'            => Document::class,
                'client_subscriptions' => ClientSubscription::class,
                'communication_logs'   => CommunicationLog::class,
                'followups'            => Followup::class,
                'satisfaction_calls'   => SatisfactionCall::class,
                'client_users'         => ClientUser::class,
                'payments_in'          => PaymentIn::class,
                'whatsapp_contacts'    => WhatsappContact::class,
                'field_visits'         => FieldVisit::class,
                'client_design_orders' => ClientDesignOrder::class,
                'system_verifications' => SystemVerification::class,
                'domains'              => Domain::class,
                'tickets'              => Ticket::class,
                'refunds'              => Refund::class,
                'coupon_redemptions'   => CouponRedemption::class,
                'client_contacts'      => ClientContact::class,
            ];

            foreach ($simpleMoves as $key => $modelClass) {
                $moved[$key] = $modelClass::withoutGlobalScopes()
                    ->where('client_id', $absorbed->id)
                    ->update(['client_id' => $survivor->id]);
            }

            // recurring_invoice_logs has a unique(tenant_id, client_id,
            // product_service_id, next_bill_date) constraint — move what
            // doesn't collide; a colliding row is a duplicate scheduling
            // artifact (not financial data), so drop the absorbed side's copy
            // and keep the survivor's existing one.
            $rilMoved = 0;
            $rilDropped = 0;
            RecurringInvoiceLog::withoutGlobalScopes()->where('client_id', $absorbed->id)->get()
                ->each(function ($log) use ($survivor, &$rilMoved, &$rilDropped) {
                    $collision = RecurringInvoiceLog::withoutGlobalScopes()
                        ->where('client_id', $survivor->id)
                        ->where('product_service_id', $log->product_service_id)
                        ->where('next_bill_date', $log->next_bill_date)
                        ->exists();
                    if ($collision) {
                        $log->delete();
                        $rilDropped++;
                    } else {
                        $log->update(['client_id' => $survivor->id]);
                        $rilMoved++;
                    }
                });
            $moved['recurring_invoice_logs'] = $rilMoved;
            $moved['recurring_invoice_logs_dropped_duplicate'] = $rilDropped;

            // Wallet: combine balances, move the ledger for audit continuity.
            $absorbedBalance = (float) $absorbed->credit_balance;
            $moved['client_credits'] = ClientCredit::withoutGlobalScopes()
                ->where('client_id', $absorbed->id)
                ->update(['client_id' => $survivor->id]);

            if ($absorbedBalance != 0) {
                $newBalance = round((float) $survivor->credit_balance + $absorbedBalance, 2);
                ClientCredit::withoutGlobalScopes()->create([
                    'tenant_id'     => $survivor->tenant_id,
                    'client_id'     => $survivor->id,
                    'type'          => 'adjustment',
                    'amount'        => $absorbedBalance,
                    'balance_after' => $newBalance,
                    'notes'         => "Wallet balance merged in from {$absorbed->name} ({$absorbed->id})",
                ]);
                $survivor->update(['credit_balance' => $newBalance]);
            }

            // Retire the absorbed client — soft-delete, never hard-delete, and
            // clear email/phone so they don't hold their unique(tenant_id, *)
            // slots hostage for reuse (a soft-deleted row still occupies them).
            $absorbed->update([
                'status' => 'merged',
                'email'  => null,
                'phone'  => null,
                'notes'  => trim(($absorbed->notes ? $absorbed->notes . "\n\n" : '')
                    . 'Merged into ' . $survivor->name . " ({$survivor->id}) on " . now()->toDateString()),
            ]);
            $absorbed->delete();

            $survivor->update([
                'notes' => trim(($survivor->notes ? $survivor->notes . "\n\n" : '')
                    . 'Absorbed ' . $absorbed->name . " ({$absorbed->id}) on " . now()->toDateString()),
            ]);

            return $moved;
        });
    }
}

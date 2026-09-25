<?php

namespace App\Http\Controllers\Concerns;

use App\Models\Document;
use App\Models\Tenant;
use App\Models\User;
use App\Models\WhatsappRenewalSession;
use App\Services\OfflinePaymentException;
use App\Services\OfflinePaymentService;
use App\Services\PaymentMessageParser;
use Illuminate\Support\Facades\Log;

/**
 * WhatsApp staff menu option 3: record an offline (mobile money / lipa namba / bank) payment against an unpaid
 * invoice. Used by WhatsappRenewalWebhookController (needs its reply(), parseYesNo(), startStaffMenu()).
 * Everything money-related goes through OfflinePaymentService — the same path as the web "Receive payments" page —
 * with NO override and NO client-credit path over WhatsApp.
 */
trait HandlesStaffPayments
{
    /** Swahili first, English underneath — staff mode is not language-scoped. */
    private function spMsg(string $sw, string $en): string
    {
        return "{$sw}\n_({$en})_";
    }

    private function spTouch(WhatsappRenewalSession $session, array $state): void
    {
        $session->update(['flow' => 'staff_pay', 'state' => $state, 'expires_at' => now()->addMinutes(15)]);
    }

    private function startStaffPayments(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff): void
    {
        if (!$staff->hasPermission('payments_in.create')) {
            Log::warning('WhatsApp staff payment refused: no permission', ['tenant_id' => $tenant->id, 'staff_id' => $staff->id]);
            $this->reply($tenant, $phone, $this->spMsg('Samahani, huna ruhusa ya kurekodi malipo. Wasiliana na msimamizi.', 'Sorry, you are not allowed to record payments. Contact your administrator.'));
            $this->startStaffMenu($tenant, $phone, $session, $staff);
            return;
        }
        $this->spTouch($session, ['step' => 'search', 'staff_id' => $staff->id]);
        $this->reply($tenant, $phone, $this->spMsg(
            "*Pokea Malipo*\nAndika jina la mteja, namba ya simu, au namba ya invoice.\nAu andika LIST kuona invoice za zamani zisizolipwa.\nRUDI = menyu ya staff.",
            'Receive Payment: type a client name, phone or invoice number, or LIST for the oldest unpaid invoices. RUDI = staff menu.'));
    }

    private function handleStaffPayStep(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, string $text): void
    {
        $state = $session->state ?? [];
        $tid = $tenant->id;

        // The session must really be this PIN-verified staff member's own (a client session can never reach here).
        if (($session->assisted_by_user_id ?? null) !== $staff->id || !$staff->is_active || $session->client_id || $session->confirmed_at) {
            Log::warning('WhatsApp staff payment refused: session/state mismatch', ['tenant_id' => $tid, 'staff_id' => $staff->id]);
            $session->delete();
            $this->reply($tenant, $phone, 'Samahani, kuna hitilafu. Tafadhali jaribu tena (andika STAFF).');
            return;
        }
        if (!$staff->hasPermission('payments_in.create')) {
            Log::warning('WhatsApp staff payment refused: no permission', ['tenant_id' => $tid, 'staff_id' => $staff->id]);
            $this->reply($tenant, $phone, $this->spMsg('Samahani, huna ruhusa ya kurekodi malipo.', 'Sorry, you are not allowed to record payments.'));
            $this->startStaffMenu($tenant, $phone, $session, $staff);
            return;
        }

        $t = trim($text);
        $step = $state['step'] ?? 'search';

        if (preg_match('/^\s*(rudi|back)\s*$/i', $t)) {
            $this->startStaffMenu($tenant, $phone, $session, $staff);
            return;
        }
        if ($t === '0' && $step !== 'search') {
            $this->spBack($tenant, $phone, $session, $staff, $state, $step);
            return;
        }

        switch ($step) {
            case 'search':
                $this->spSearch($tenant, $phone, $session, $staff, $state, $t);
                return;
            case 'pick_invoice':
                if (preg_match('/^[1-9]$/', $t) && !empty($state['invoice_ids'][(int) $t - 1])) {
                    $doc = $this->spLoadInvoice($tid, $state['invoice_ids'][(int) $t - 1]);
                    if (!$doc) {
                        $this->reply($tenant, $phone, $this->spMsg('Invoice hiyo haipatikani tena au imeshalipwa. Tafuta upya.', 'That invoice is no longer available. Search again.'));
                        $this->spTouch($session, ['step' => 'search', 'staff_id' => $staff->id]);
                        return;
                    }
                    $state['invoice_id'] = $doc->id;
                    $this->spAskMethod($tenant, $phone, $session, $staff, $state, $doc);
                    return;
                }
                if (preg_match('/^\d+$/', $t)) {
                    $this->reply($tenant, $phone, $this->spMsg('Chagua namba kutoka kwenye orodha, au andika utafutaji mpya.', 'Pick a number from the list, or type a new search.'));
                    return;
                }
                $this->spSearch($tenant, $phone, $session, $staff, $state, $t);
                return;
            case 'method':
                $methods = OfflinePaymentService::methodsFor($tenant);
                if (preg_match('/^[1-9]$/', $t) && isset($methods[(int) $t - 1])) {
                    $state['method'] = $methods[(int) $t - 1]['value'];
                    $state['method_label'] = $methods[(int) $t - 1]['label'];
                    $state['step'] = 'reference';
                    $this->spTouch($session, $state);
                    $this->reply($tenant, $phone, $this->spMsg(
                        "Andika namba ya kumbukumbu ya muamala (Transaction ID / Ref). Unaweza pia kubandika ujumbe mzima wa malipo.\n0) Rudi",
                        'Type the transaction ID / reference, or paste the whole payment message.'));
                    return;
                }
                $this->reply($tenant, $phone, $this->spMsg('Chagua namba ya njia ya malipo.', 'Pick a payment method number.'));
                $this->spAskMethod($tenant, $phone, $session, $staff, $state, $this->spLoadInvoice($tid, $state['invoice_id'] ?? ''));
                return;
            case 'reference':
                $this->spReference($tenant, $phone, $session, $staff, $state, $t);
                return;
            case 'confirm_parsed':
                $yn = $this->parseYesNo($t);
                if ($yn === true) {
                    $state['reference'] = $state['parsed_ref'];
                    $this->spAcceptReference($tenant, $phone, $session, $staff, $state);
                } elseif ($yn === false) {
                    $state['step'] = 'reference';
                    unset($state['parsed_ref'], $state['parsed_amount']);
                    $this->spTouch($session, $state);
                    $this->reply($tenant, $phone, $this->spMsg('Sawa. Andika namba ya kumbukumbu mwenyewe.', 'OK. Type the reference yourself.'));
                } else {
                    $this->reply($tenant, $phone, $this->spMsg("Jibu 1 au 2.\n1) Ndiyo\n2) Hapana", 'Reply 1 or 2.'));
                }
                return;
            case 'amount':
                $this->spAmountChoice($tenant, $phone, $session, $staff, $state, $t);
                return;
            case 'amount_other':
                $this->spAmountOther($tenant, $phone, $session, $staff, $state, $t);
                return;
            case 'confirm':
                $yn = $this->parseYesNo($t);
                if ($yn === true) {
                    $this->spRecord($tenant, $phone, $session, $staff, $state);
                } elseif ($yn === false) {
                    $this->reply($tenant, $phone, $this->spMsg('Sawa, halijarekodiwa.', 'OK, nothing was recorded.'));
                    $this->startStaffMenu($tenant, $phone, $session, $staff);
                } else {
                    $this->reply($tenant, $phone, $this->spMsg("Jibu 1 au 2.\n1) Ndiyo, rekodi\n2) Hapana", 'Reply 1 or 2.'));
                }
                return;
        }

        $this->startStaffMenu($tenant, $phone, $session, $staff);
    }

    private function spBack(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, array $state, string $step): void
    {
        $doc = $this->spLoadInvoice($tenant->id, $state['invoice_id'] ?? '');
        match ($step) {
            'pick_invoice' => $this->startStaffPayments($tenant, $phone, $session, $staff),
            'method' => $this->startStaffPayments($tenant, $phone, $session, $staff),
            'reference', 'confirm_parsed' => $doc ? $this->spAskMethod($tenant, $phone, $session, $staff, $state, $doc) : $this->startStaffPayments($tenant, $phone, $session, $staff),
            default => $doc ? $this->spAskMethod($tenant, $phone, $session, $staff, $state, $doc) : $this->startStaffPayments($tenant, $phone, $session, $staff),
        };
    }

    /** Tenant-scoped, still-unpaid invoice with its live balance, or null. */
    private function spLoadInvoice(string $tenantId, string $id): ?Document
    {
        if ($id === '') {
            return null;
        }

        return OfflinePaymentService::unpaidQuery($tenantId)->whereKey($id)->first();
    }

    private function spSearch(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, array $state, string $t): void
    {
        $q = OfflinePaymentService::unpaidQuery($tenant->id);
        $isList = $t === '' || $t === '0' || preg_match('/^\s*list\s*$/i', $t);
        if (!$isList) {
            OfflinePaymentService::applySearch($q, $t, $tenant->id);
        }
        $total = (clone $q)->count();
        $docs = $q->limit(9)->get();

        if ($docs->isEmpty()) {
            $this->reply($tenant, $phone, $this->spMsg(
                $isList ? 'Hakuna invoice zisizolipwa.' : "Hakuna invoice isiyolipwa iliyopatikana kwa \"{$t}\". Jaribu jina, namba ya simu au namba ya invoice.",
                'No unpaid invoices found.'));
            $this->spTouch($session, ['step' => 'search', 'staff_id' => $staff->id]);
            return;
        }

        $lines = [];
        foreach ($docs as $i => $d) {
            $lines[] = ($i + 1) . ") {$d->document_number} — " . ($d->client?->name ?? '—') . ' — salio TZS ' . number_format(OfflinePaymentService::balanceOf($d))
                . ($this->spIsOverdue($d) ? ' — ⚠️ imechelewa' : '');
        }
        if ($total > 9) {
            $lines[] = "\nZinaonyeshwa 9 kati ya {$total}. Kuwa mahususi zaidi ukitafuta. (Showing 9 of {$total}; refine your search.)";
        }
        $this->spTouch($session, ['step' => 'pick_invoice', 'staff_id' => $staff->id, 'invoice_ids' => $docs->pluck('id')->all()]);
        $this->reply($tenant, $phone, implode("\n", $lines) . "\n\nJibu na namba kuchagua. 0 = rudi, RUDI = menyu.");
    }

    private function spIsOverdue(Document $d): bool
    {
        return $d->status === 'overdue' || ($d->due_date && $d->due_date->format('Y-m-d') < now()->toDateString());
    }

    private function spAskMethod(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, array $state, ?Document $doc): void
    {
        if (!$doc) {
            $this->startStaffPayments($tenant, $phone, $session, $staff);
            return;
        }
        $methods = array_slice(OfflinePaymentService::methodsFor($tenant), 0, 9);
        $state['step'] = 'method';
        $state['invoice_id'] = $doc->id;
        $this->spTouch($session, $state);
        $bal = OfflinePaymentService::balanceOf($doc);
        $paid = (float) $doc->total - $bal;
        $lines = ["*Invoice {$doc->document_number}*", "Mteja: " . ($doc->client?->name ?? '—'),
            'Jumla: TZS ' . number_format((float) $doc->total) . ' | Imelipwa: TZS ' . number_format($paid) . ' | Salio: TZS ' . number_format($bal), '',
            'Njia ya malipo? (Payment method)'];
        foreach ($methods as $i => $m) {
            $lines[] = ($i + 1) . ") {$m['label']}";
        }
        $lines[] = '0) Rudi';
        $this->reply($tenant, $phone, implode("\n", $lines));
    }

    private function spReference(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, array $state, string $t): void
    {
        // A plain code (no spaces): use it as typed.
        if (preg_match('#^[A-Za-z0-9._\-/]{4,40}$#', $t)) {
            $state['reference'] = $t;
            $this->spAcceptReference($tenant, $phone, $session, $staff, $state);
            return;
        }
        // A pasted message: extract, and ALWAYS ask staff to confirm what was understood.
        $p = PaymentMessageParser::parse($t);
        if ($p['reference'] && strlen($p['reference']) >= 4 && strlen($p['reference']) <= 40) {
            $state['step'] = 'confirm_parsed';
            $state['parsed_ref'] = $p['reference'];
            $state['parsed_amount'] = $p['amount'];
            $this->spTouch($session, $state);
            $this->reply($tenant, $phone, $this->spMsg(
                "Nimeelewa:\n• Kumbukumbu: {$p['reference']}" . ($p['amount'] ? "\n• Kiasi: TZS " . number_format($p['amount']) : '') . ($p['name'] ? "\n• Mtumaji: {$p['name']}" : '') . "\n\nSahihi?\n1) Ndiyo\n2) Hapana",
                'Is this correct?'));
            return;
        }
        $this->reply($tenant, $phone, $this->spMsg('Namba ya kumbukumbu lazima iwe herufi/namba 4 hadi 40 bila nafasi. Jaribu tena au bandika ujumbe mzima.', 'The reference must be 4-40 letters/digits without spaces. Try again or paste the whole message.'));
    }

    private function spAcceptReference(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, array $state): void
    {
        $ref = trim($state['reference']);
        // same guard as the web page, but here there is NO override
        $dup = OfflinePaymentService::findDuplicate($tenant->id, $state['method'], $ref);
        if ($dup) {
            $dd = $dup->document_id ? Document::withoutGlobalScopes()->where('tenant_id', $tenant->id)->find($dup->document_id) : null;
            Log::warning('WhatsApp staff payment refused: duplicate reference', ['tenant_id' => $tenant->id, 'staff_id' => $staff->id, 'payment_id' => $dup->id]);
            $state['step'] = 'reference';
            unset($state['reference'], $state['parsed_ref'], $state['parsed_amount']);
            $this->spTouch($session, $state);
            $this->reply($tenant, $phone, $this->spMsg(
                'Kumbukumbu hii tayari imetumika' . ($dd ? " kwa Invoice {$dd->document_number}" : '') . '. Hakikisha si malipo yale yale. Andika kumbukumbu nyingine, au tumia tovuti kama ni malipo tofauti.',
                'This reference was already used. If it is a genuinely different payment, record it on the web page.'));
            return;
        }
        $doc = $this->spLoadInvoice($tenant->id, $state['invoice_id'] ?? '');
        if (!$doc) {
            $this->reply($tenant, $phone, $this->spMsg('Invoice haipatikani tena au imeshalipwa.', 'That invoice is no longer payable.'));
            $this->startStaffMenu($tenant, $phone, $session, $staff);
            return;
        }
        $bal = OfflinePaymentService::balanceOf($doc);
        $state['step'] = 'amount';
        $state['balance'] = $bal;
        $this->spTouch($session, $state);
        $opts = ['1) Lipa salio lote (TZS ' . number_format($bal) . ')', '2) Kiasi kingine'];
        $pa = $state['parsed_amount'] ?? null;
        if ($pa && $pa > 0 && $pa <= $bal && abs($pa - $bal) > 0.009) {
            $opts[] = '3) TZS ' . number_format($pa) . ' (kutoka kwenye ujumbe)';
        }
        $this->reply($tenant, $phone, $this->spMsg("Kiasi kilicholipwa?\n" . implode("\n", $opts) . "\n0) Rudi", 'Amount paid?'));
    }

    private function spAmountChoice(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, array $state, string $t): void
    {
        $bal = (float) ($state['balance'] ?? 0);
        $pa = $state['parsed_amount'] ?? null;
        if ($t === '1') {
            $this->spConfirm($tenant, $phone, $session, $staff, $state, $bal);
        } elseif ($t === '2') {
            $state['step'] = 'amount_other';
            $this->spTouch($session, $state);
            $this->reply($tenant, $phone, $this->spMsg('Andika kiasi (TZS), mfano 25000.', 'Type the amount in TZS.'));
        } elseif ($t === '3' && $pa && $pa > 0 && $pa <= $bal) {
            $this->spConfirm($tenant, $phone, $session, $staff, $state, (float) $pa);
        } else {
            $this->reply($tenant, $phone, $this->spMsg('Jibu 1 au 2.', 'Reply with a listed number.'));
        }
    }

    private function spAmountOther(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, array $state, string $t): void
    {
        $clean = preg_replace('/(tzs|tsh|shs?|\s)/i', '', $t);
        $clean = str_replace(',', '', $clean);
        if (!preg_match('/^\d+(\.\d{1,2})?$/', $clean) || (float) $clean <= 0) {
            $this->reply($tenant, $phone, $this->spMsg('Kiasi si sahihi. Andika namba tu, mfano 25000.', 'Invalid amount. Type digits only, e.g. 25000.'));
            return;
        }
        $amt = round((float) $clean, 2);
        $bal = (float) ($state['balance'] ?? 0);
        if ($amt > $bal + 0.001) {
            $this->reply($tenant, $phone, $this->spMsg(
                'Kiasi kinazidi salio (TZS ' . number_format($bal) . '). Malipo ya ziada hayarekodiwi kwa WhatsApp - tumia ukurasa wa "Receive payments" kwenye tovuti.',
                'The amount exceeds the balance. Overpayments cannot be recorded over WhatsApp - use the Receive payments page on the web.'));
            return;
        }
        $this->spConfirm($tenant, $phone, $session, $staff, $state, $amt);
    }

    private function spConfirm(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, array $state, float $amount): void
    {
        $doc = $this->spLoadInvoice($tenant->id, $state['invoice_id'] ?? '');
        if (!$doc) {
            $this->reply($tenant, $phone, $this->spMsg('Invoice haipatikani tena au imeshalipwa.', 'That invoice is no longer payable.'));
            $this->startStaffMenu($tenant, $phone, $session, $staff);
            return;
        }
        $bal = OfflinePaymentService::balanceOf($doc);
        $state['step'] = 'confirm';
        $state['amount'] = $amount;
        $this->spTouch($session, $state);
        $this->reply($tenant, $phone, $this->spMsg(
            "*Thibitisha malipo*\n• Mteja: " . ($doc->client?->name ?? '—') . "\n• Invoice: {$doc->document_number}\n• Njia: {$state['method_label']}\n• Kumbukumbu: {$state['reference']}\n• Kiasi: TZS " . number_format($amount)
            . "\n• Salio jipya: TZS " . number_format(max(0, $bal - $amount)) . "\n\nRekodi?\n1) Ndiyo, rekodi\n2) Hapana",
            'Confirm: record this payment?'));
    }

    private function spRecord(Tenant $tenant, string $phone, WhatsappRenewalSession $session, User $staff, array $state): void
    {
        $invoiceId = (string) ($state['invoice_id'] ?? '');
        $amount = (float) ($state['amount'] ?? 0);
        $ref = (string) ($state['reference'] ?? '');
        try {
            $r = app(\App\Services\OfflinePaymentService::class)->record($staff, [$invoiceId], $amount, [
                'method' => $state['method'] ?? '', 'payment_date' => now()->toDateString(), 'reference' => $ref,
                'notes' => 'Recorded via WhatsApp staff menu', 'send_receipt' => true, 'allow_excess' => false, 'confirm_different' => false,
                'idempotency_key' => 'wa-staff:' . hash('sha256', $staff->id . '|' . $invoiceId . '|' . strtolower($ref) . '|' . number_format($amount, 2, '.', '')),
            ]);
        } catch (OfflinePaymentException $e) {
            Log::warning('WhatsApp staff payment refused', ['tenant_id' => $tenant->id, 'staff_id' => $staff->id, 'code' => $e->errorCode, 'document_id' => $invoiceId]);
            $msg = match ($e->errorCode) {
                'duplicate_reference' => $this->spMsg('Kumbukumbu hii tayari imetumika' . (!empty($e->extra['existing']['document_number']) ? " kwa Invoice {$e->extra['existing']['document_number']}" : '') . '. Haikurekodiwa.', 'This reference was already used. Not recorded.'),
                'recent_same_amount' => $this->spMsg('Malipo ya kiasi hiki hiki yalirekodiwa dakika chache zilizopita kwa invoice hii. Haikurekodiwa mara ya pili.', 'The same amount was just recorded for this invoice. Not recorded again.'),
                'invoice_not_payable', 'not_found' => $this->spMsg('Invoice hii haiwezi kupokea malipo (imeshalipwa au imeghairiwa). Haikurekodiwa.', 'This invoice cannot receive payments. Not recorded.'),
                'exceeds_balance' => $this->spMsg('Kiasi kinazidi salio. Tumia ukurasa wa "Receive payments" kwenye tovuti.', 'Amount exceeds the balance; use the web page.'),
                default => $this->spMsg('Malipo hayajarekodiwa: ' . $e->getMessage(), 'Not recorded.'),
            };
            $this->reply($tenant, $phone, $msg);
            $this->startStaffMenu($tenant, $phone, $session, $staff);
            return;
        } catch (\Throwable $e) {
            report($e);
            Log::error('WhatsApp staff payment failed', ['tenant_id' => $tenant->id, 'staff_id' => $staff->id, 'error' => $this->logSafe($e)]);
            $this->reply($tenant, $phone, $this->spMsg('Hitilafu imetokea, malipo hayajarekodiwa. Jaribu tena au tumia tovuti.', 'An error occurred; nothing was recorded.'));
            $this->startStaffMenu($tenant, $phone, $session, $staff);
            return;
        }

        $inv = $r['invoices'][0];
        Log::info('WhatsApp staff payment recorded', ['tenant_id' => $tenant->id, 'staff_id' => $staff->id, 'document_id' => $inv['document_id'], 'payment_id' => $inv['payment_id'], 'replayed' => $r['replayed']]);
        $paid = $inv['status'] === 'paid';
        $line = $r['replayed'] ? 'Malipo haya tayari yalirekodiwa. ✅ ' : 'Imerekodiwa ✅ ';
        $line .= "Invoice {$inv['document_number']} sasa ni " . ($paid ? 'PAID' : 'PARTIAL, salio TZS ' . number_format($inv['balance_after']));
        if ($paid && !$r['replayed']) {
            $line .= "\nRisiti imetumwa kwa mteja.";
        }
        $this->reply($tenant, $phone, $line);
        $this->startStaffMenu($tenant, $phone, $session, $staff);
    }
}

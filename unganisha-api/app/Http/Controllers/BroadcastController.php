<?php

namespace App\Http\Controllers;

use App\Jobs\SendBroadcastJob;
use App\Models\Broadcast;
use App\Models\Client;
use App\Services\MosmsService;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

class BroadcastController extends Controller
{
    public function index(Request $request)
    {
        $broadcasts = Broadcast::with('sender:id,name')
            ->orderByDesc('created_at')
            ->paginate($request->input('per_page', 15));

        return response()->json($broadcasts);
    }

    /** Lists this tenant's own MoSMS address book, for the "MoSMS Contacts" source picker. */
    public function mosmsContacts(Request $request)
    {
        $tenant = \App\Models\Tenant::withoutGlobalScopes()->find($request->user()->tenant_id);
        $contacts = app(MosmsService::class)->contacts($tenant);

        return response()->json([
            'data' => collect($contacts)->map(fn (array $c) => [
                'phone' => $c['phone'],
                'name' => $c['name'],
                'email' => $c['email'],
            ])->values(),
        ]);
    }

    /**
     * Resolve who a broadcast on this channel would actually reach — same
     * query `send()` uses, minus creating/dispatching anything. Lets staff
     * check the recipient list (and see how many duplicate contacts get
     * skipped) before committing to a real send.
     */
    public function preview(Request $request)
    {
        $request->validate([
            'channel' => 'required|in:email,sms,whatsapp,both',
            'sources' => 'nullable|array',
            'sources.*' => 'in:mobilling,mosms_contacts',
            'client_ids' => 'nullable|array',
            'client_ids.*' => 'uuid|exists:clients,id',
            'contact_phones' => 'nullable|array',
            'contact_phones.*' => 'string',
        ]);

        [$recipients, $duplicatesRemoved] = $this->resolveRecipients($request, $this->requestedSources($request), $request->channel);

        return response()->json([
            'total' => $recipients->count(),
            'duplicates_removed' => $duplicatesRemoved,
            'recipients' => $recipients->map(fn (array $r) => [
                'name' => $r['name'],
                'email' => $r['email'],
                'phone' => $r['phone'],
            ])->values(),
        ]);
    }

    public function send(Request $request)
    {
        $request->validate([
            'channel'    => 'required|in:email,sms,whatsapp,both',
            'subject'    => 'required_if:channel,email,both|nullable|string|max:255',
            'body'       => 'required_if:channel,email,both|nullable|string',
            'sms_body'   => 'required_if:channel,sms,both|nullable|string|max:160',
            'whatsapp_body' => 'required_if:channel,whatsapp|nullable|string|max:4096',
            // Capped at 2MB — this server's upload_max_filesize is 2M, so anything larger
            // never reaches this validation (PHP drops it before Laravel sees the request).
            'whatsapp_image' => 'nullable|image|mimes:jpeg,png,webp|max:2048',
            'sources' => 'nullable|array',
            'sources.*' => 'in:mobilling,mosms_contacts',
            'client_ids' => 'nullable|array',
            'client_ids.*' => 'uuid|exists:clients,id',
            'contact_phones' => 'nullable|array',
            'contact_phones.*' => 'string',
        ]);

        $channel = $request->channel;
        $sources = $this->requestedSources($request);

        [$recipients, $duplicatesRemoved] = $this->resolveRecipients($request, $sources, $channel);

        $imagePath = null;
        if ($request->hasFile('whatsapp_image')) {
            $imagePath = $request->file('whatsapp_image')->store('whatsapp-posters', 'public');
        }

        // Create broadcast record
        $broadcast = Broadcast::create([
            'sent_by'          => $request->user()->id,
            'client_ids'       => in_array('mobilling', $sources, true) ? $request->client_ids : null,
            'total_recipients' => $recipients->count(),
            'channel'          => $channel,
            'subject'          => $request->subject,
            'body'             => $request->body,
            'sms_body'         => $request->sms_body,
            'whatsapp_body'    => $request->whatsapp_body,
            'whatsapp_image_path' => $imagePath,
            'sent_count'       => 0,
            'failed_count'     => 0,
        ]);

        // Runs on the dedicated 'broadcasts' queue worker — see SendBroadcastJob
        // for why (WhatsApp sends are throttled, so a large list can genuinely
        // take minutes, well past anything safe to run inline on a web worker).
        SendBroadcastJob::dispatch($broadcast->id, $recipients->all())
            ->onConnection('database')
            ->onQueue('broadcasts');

        $dupeNote = $duplicatesRemoved > 0 ? " ({$duplicatesRemoved} duplicate contact(s) skipped)" : '';

        return response()->json([
            'message'          => "Broadcast started for {$recipients->count()} recipient(s){$dupeNote} — sending in the background. Refresh History for live progress.",
            'broadcast_id'     => $broadcast->id,
            'total_recipients' => $recipients->count(),
            'duplicates_removed' => $duplicatesRemoved,
        ], 202);
    }

    /** List the clients a broadcast did or didn't reach — for "which ones failed, and why?" */
    public function recipients(Request $request, Broadcast $broadcast)
    {
        $status = $request->input('status', 'failed');
        $rows = $status === 'sent' ? ($broadcast->sent_client_ids ?? []) : ($broadcast->failed_client_ids ?? []);
        $reasons = $broadcast->failure_reasons ?? [];

        // Old broadcasts (pre-dated recipient snapshots) stored bare Client UUID
        // strings here — look those up for display. Newer ones store the full
        // {key, name, phone, email, client_id} snapshot directly, which also
        // covers non-Client recipients (e.g. MoSMS contacts) that a DB lookup
        // could never resolve.
        $legacyIds = collect($rows)->filter(fn ($r) => is_string($r))->values();
        $legacyClients = $legacyIds->isEmpty() ? collect() : Client::withoutGlobalScopes()
            ->whereIn('id', $legacyIds)
            ->get(['id', 'name', 'email', 'phone'])
            ->keyBy('id');

        $data = collect($rows)->map(function ($row) use ($legacyClients, $reasons, $status) {
            if (is_string($row)) {
                $client = $legacyClients->get($row);

                return [
                    'id' => $row,
                    'name' => $client->name ?? 'Unknown client (removed)',
                    'email' => $client->email ?? null,
                    'phone' => $client->phone ?? null,
                    'reason' => $status === 'failed' ? ($reasons[$row] ?? null) : null,
                ];
            }

            return [
                'id' => $row['client_id'] ?? $row['key'] ?? null,
                'name' => $row['name'] ?? 'Unknown',
                'email' => $row['email'] ?? null,
                'phone' => $row['phone'] ?? null,
                'reason' => $status === 'failed' ? ($row['reason'] ?? ($reasons[$row['key'] ?? ''] ?? null)) : null,
            ];
        })->values();

        return response()->json(['data' => $data]);
    }

    /** Re-send the exact same content to only the recipients who failed last time — never the ones already reached. */
    public function resendFailed(Request $request, Broadcast $broadcast)
    {
        $failed = $broadcast->failed_client_ids ?? [];
        if (empty($failed)) {
            return response()->json(['message' => 'No failed recipients to resend to.'], 422);
        }

        // Normalize to the recipient-snapshot shape SendBroadcastJob expects —
        // old broadcasts stored bare Client UUIDs, so re-derive a snapshot for those.
        $isLegacy = is_string($failed[0] ?? null);
        $recipients = $isLegacy
            ? Client::withoutGlobalScopes()->whereIn('id', $failed)->get()->map(fn (Client $c) => [
                'key' => 'client:' . $c->id,
                'client_id' => $c->id,
                'name' => $c->name,
                'phone' => $c->phone,
                'email' => $c->email,
            ])->all()
            : $failed;

        $retry = Broadcast::create([
            'sent_by'          => $request->user()->id,
            'client_ids'       => $isLegacy ? $failed : null,
            'total_recipients' => count($recipients),
            'channel'          => $broadcast->channel,
            'subject'          => $broadcast->subject,
            'body'             => $broadcast->body,
            'sms_body'         => $broadcast->sms_body,
            'whatsapp_body'    => $broadcast->whatsapp_body,
            'whatsapp_image_path' => $broadcast->whatsapp_image_path,
            'sent_count'       => 0,
            'failed_count'     => 0,
            'retry_of_broadcast_id' => $broadcast->id,
        ]);

        SendBroadcastJob::dispatch($retry->id, $recipients)
            ->onConnection('database')
            ->onQueue('broadcasts');

        return response()->json([
            'message'          => 'Resend started for ' . count($recipients) . ' recipient(s) — refresh History for live progress.',
            'broadcast_id'     => $retry->id,
            'total_recipients' => count($recipients),
        ], 202);
    }

    /** @return string[] */
    private function requestedSources(Request $request): array
    {
        if ($request->filled('sources')) {
            return array_values(array_unique((array) $request->input('sources')));
        }
        // Back-compat with the old single `source` field.
        return [$request->input('source', 'mobilling')];
    }

    /**
     * Eligible recipients across every selected source/channel combo, with
     * duplicate contacts collapsed — two records sharing the same phone (or
     * email, for an email send), even across DIFFERENT sources, would
     * otherwise each get notified separately, so the same person gets the
     * message twice.
     *
     * @param string[] $sources
     * @return array{0: Collection<int, array{key: string, client_id: ?string, name: ?string, phone: ?string, email: ?string}>, 1: int} [deduped recipients, how many duplicates were dropped]
     */
    private function resolveRecipients(Request $request, array $sources, string $channel): array
    {
        $raw = [];
        foreach (array_unique($sources) as $source) {
            $raw = array_merge($raw, $source === 'mosms_contacts'
                ? $this->mosmsContactRecipients($request, $channel)
                : $this->mobillingClientRecipients($request, $channel));
        }

        $deduped = collect($raw)->unique(fn (array $r) => $this->recipientDedupKey($r, $channel))->values();

        return [$deduped, count($raw) - $deduped->count()];
    }

    private function mobillingClientRecipients(Request $request, string $channel): array
    {
        // BelongsToTenant auto-scopes this to the current tenant.
        $query = Client::query();

        if ($request->filled('client_ids')) {
            $query->whereIn('id', $request->client_ids);
        }

        if ($channel === 'email') {
            $query->whereNotNull('email')->where('email', '!=', '');
        } elseif (in_array($channel, ['sms', 'whatsapp'], true)) {
            $query->whereNotNull('phone')->where('phone', '!=', '');
        } else {
            // 'both' — need at least one contact method
            $query->where(function ($q) {
                $q->where(function ($q2) {
                    $q2->whereNotNull('email')->where('email', '!=', '');
                })->orWhere(function ($q2) {
                    $q2->whereNotNull('phone')->where('phone', '!=', '');
                });
            });
        }

        return $query->get()->map(fn (Client $c) => [
            'key' => 'client:' . $c->id,
            'client_id' => $c->id,
            'name' => $c->name,
            'phone' => $c->phone,
            'email' => $c->email,
        ])->all();
    }

    /** This tenant's own MoSMS address book — never another tenant's. */
    private function mosmsContactRecipients(Request $request, string $channel): array
    {
        $tenant = \App\Models\Tenant::withoutGlobalScopes()->find($request->user()->tenant_id);
        $contacts = app(MosmsService::class)->contacts($tenant);

        // Staff picked specific contacts rather than "everyone" — match by
        // normalized phone, same comparison the dedup key itself uses.
        $selectedPhones = $request->filled('contact_phones')
            ? collect((array) $request->input('contact_phones'))->map(fn ($p) => $this->normalizePhone($p))->all()
            : null;

        return collect($contacts)
            ->filter(function (array $c) use ($channel, $selectedPhones) {
                if ($selectedPhones !== null) {
                    $normalized = $c['phone'] ? $this->normalizePhone($c['phone']) : null;
                    if (!$normalized || !in_array($normalized, $selectedPhones, true)) {
                        return false;
                    }
                }

                $hasEmail = !empty($c['email']);
                $hasPhone = !empty($c['phone']);

                return match ($channel) {
                    'email' => $hasEmail,
                    'sms', 'whatsapp' => $hasPhone,
                    default => $hasEmail || $hasPhone,
                };
            })
            ->map(fn (array $c) => [
                'key' => 'mosms_contact:' . ($c['phone'] ? $this->normalizePhone($c['phone']) : strtolower(trim((string) $c['email']))),
                'client_id' => null,
                'name' => $c['name'] ?: ($c['phone'] ?? $c['email'] ?? 'Unknown'),
                'phone' => $c['phone'],
                'email' => $c['email'],
            ])
            ->values()
            ->all();
    }

    /** Two recipients are "the same person" for this channel if they'd get the exact same message(s). */
    private function recipientDedupKey(array $recipient, string $channel): string
    {
        $phone = $recipient['phone'] ? $this->normalizePhone($recipient['phone']) : null;
        $email = $recipient['email'] ? strtolower(trim($recipient['email'])) : null;

        return match ($channel) {
            'email' => 'email:' . $email,
            'sms', 'whatsapp' => 'phone:' . $phone,
            default => 'phone:' . $phone . '|email:' . $email, // 'both'
        };
    }

    /** Mirrors WhatsAppService::formatPhone() — same normalization, so "0712..." and "255712..." collapse to one key. */
    private function normalizePhone(string $phone): string
    {
        $phone = preg_replace('/[^0-9]/', '', $phone);

        if (str_starts_with($phone, '0') && strlen($phone) <= 10) {
            $phone = '255' . substr($phone, 1);
        }

        return $phone;
    }
}

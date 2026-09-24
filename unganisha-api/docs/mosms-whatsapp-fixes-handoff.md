# MoSMS changes needed for the MoBilling WhatsApp bot (hand-off)

Paths are relative to `MoSmS/backend`. Line numbers refer to the current `WhatsAppWebhookController.php` (582 lines) and may drift.
MoBilling side is already done and pushed (bare-1 handling, MENU everywhere, media marker, rate limit, message splitting).
MoBilling endpoints: `POST /api/webhooks/mosms/menu` (`text`), `POST /api/webhooks/mosms/renewal-reply`.

## 1. Forward a `[media]` marker for non-text messages (H2) - required
`app/Http/Controllers/WhatsAppWebhookController.php`, `handleInbound()` L135-138. Today a non-text message gives `$text = null` and
is dropped (MoBilling `menu()` even receives nothing). Change:

```php
$text = (string) ($this->extractReply($message) ?? '');
$type = $message['type'] ?? null;
if ($text === '' && in_array($type, ['image','audio','video','document','sticker','location','reaction','contacts'], true)) {
    $text = '[media]';            // MoBilling replies "text only, contact staff" and alerts staff (bank receipts!)
} elseif ($text === '' && $type === 'unsupported') {
    $text = '[unsupported]';
}
```
Only the MoBilling routes (`handleMobillingMenuMessage`, L240-250, L285-290, L345-350) need the marker; other flows (pledge/RSVP/registration)
should keep treating it as "no text" - guard them with `$text !== '[media]' && $text !== '[unsupported]'`, or check `$type` there.
MoBilling matches the marker case-insensitively and exactly (`[media]`, `[unsupported]`).

## 2. Bare "1" must not be routed blindly to renewal-reply (H1)
L253-272: any bare `1` within 9 days of a message containing "MoBilling Renewal" goes to `/webhooks/mosms/renewal-reply`.
MoBilling's `confirm()` is now safe: if the phone has a live session in a flow (language 1) English, 1) Pay online, 1) Yes ...) or
without renewal items, it treats the "1" as a normal menu digit. So no MoSMS change is strictly required.
Do NOT "always forward 1 to /menu": with a genuine reminder session at the root, `/menu` would read 1 as "Domain Registration".
Optional hardening: only take this branch when the LAST outbound message to that phone (`mostRecentWhatsappSenderTenant`-style query,
L391-398) is the renewal reminder, i.e. add `->where('id', '>=', <id of last message>)` / compare the latest message body.

## 3. Cold start for unknown first contact
L285-290 only starts MoBilling on keywords (`mobilling|huduma|staff|wafanyakazi`). For any other first-contact text on the MoBilling WABA
number with no recent-sender match, reply (via the MoBilling tenant's session send) with:
`Andika MOBILLING kupata menyu. / Type MOBILLING to get the menu.` instead of silence.

## 4. Dedupe by `wa_message_id`
`InboundMessage::create` (L~150) stores `'wa_message_id' => $message['id']` but nothing prevents Meta retries from being processed twice.
- Migration: unique index on `(channel, wa_message_id)` (nullable ok).
- In `handleInbound()` right before create: `if ($id && InboundMessage::where('wa_message_id', $id)->exists()) return;`
  (or `firstOrCreate` and return when `!wasRecentlyCreated`; catch the unique-violation race).

## 5. Per-phone rate limit
Add at the top of `handleInbound()` after `$from` is known:
```php
$key = 'wa_in:' . $from;
Cache::add($key, 0, 600);
if (Cache::increment($key) > 60) { return; }   // MoBilling has its own 30/10min guard + polite notice
```

## 6. Alert when whatsapp_balance < 1
`app/Http/Controllers/Tenant/SmsController.php` `sendWhatsappSession()` L169-170 (and `sendWhatsappCtaUrl()` L204-205) return 422
"Insufficient WhatsApp balance" silently; the bot then goes mute. Before returning 422: log at `error` level with the tenant id and notify the
tenant owner once per hour (`Cache::add("wa_low_balance:{$tenant->id}", 1, 3600)`). MoBilling already alerts its own staff once/hour when
this 422 message reaches it, but MoSMS is the right place to email the account owner too.

## 7. Split messages over 4000 chars
WhatsApp text max is 4096. In `WhatsAppCloudService` session-text send, chunk on line boundaries (<= 3900 chars) and send sequentially.
MoBilling already splits its own replies at 3900, so this is a safety net for other callers.

## 8. Redact sensitive text from the inbound log line
L140: `Log::info('WhatsApp inbound message', ['from' => $from, 'text' => $text, ...])` logs raw text, which can include a domain EPP/auth code
(WhatsApp "transfer domain" flow), PINs (staff PIN) and emails. Log length and type only, or mask when the text looks like a code:
```php
Log::info('WhatsApp inbound message', ['from' => $from, 'len' => mb_strlen((string) $text), 'type' => $message['type'] ?? null]);
```
Also check `InboundMessage` `body`/`text` storage (L~150) - consider not persisting texts while the MoBilling session is in an EPP/PIN step, or
truncating/masking them.

## 9. Sticky routing instead of "most recent sender"
`mostRecentWhatsappSenderTenant()` (L391-398) picks whichever tenant last messaged the phone; any unrelated MoSMS broadcast flips a client
out of a live MoBilling conversation. Suggested: a small table/cache `whatsapp_conversation_routes(phone, tenant_id, expires_at)` written
when a MoBilling menu/renewal callback succeeds (`handleMobillingMenuMessage`, L440-466) with a 30-minute sliding TTL (matches MoBilling's
session expiry); consult it first in `handleInbound()` and fall back to the most-recent-sender heuristic only when absent.

## 10. Send the WhatsApp message id to MoBilling (idempotency, phase 3)
`handleMobillingMenuMessage()` (L440-466) posts only `secret`, `mosms_tenant_id`, `phone` and `text` to `/webhooks/mosms/menu`. Please also pass
`message_id` (Meta's `wa_message_id`, the same value item 4 dedupes on) in that payload and in the renewal-reply callback. Until then MoBilling
uses a stop-gap: an identical (phone, text) within 3 seconds is ignored, and each phone's messages are processed one at a time (per-phone lock)
so a retried "YES" cannot create a second order/invoice/reboot. Once `message_id` arrives, MoBilling will dedupe on (tenant, message_id) with a 24h
TTL instead, which is exact and does not swallow a client who genuinely sends the same digit twice quickly.

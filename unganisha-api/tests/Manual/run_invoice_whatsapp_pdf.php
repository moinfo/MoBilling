<?php
// php tests/Manual/run_invoice_whatsapp_pdf.php
// Live DB, EVERY scenario rolled back. ALL external HTTP faked (Http::fake + preventStrayRequests) —
// nothing here ever reaches graph.facebook.com or mosms.co.tz for real.
//
// Covers DocumentController::sendWhatsApp's PDF-attachment path (WhatsAppService::sendDocument —
// the Meta upload-then-document-message flow — plus the full itemized companion text message) and
// its text-only fallback (MoSMS-routed tenants, pesapal-disabled tenants, any Meta failure), the
// unchanged refusal cases, tenant isolation, and the InvoiceSentNotification::toWhatsApp() fix that
// now always includes offline payment-method details alongside a pay-online link.
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\DocumentController;
use App\Models\{Client, Document, MosmsAccount, Tenant, User};
use App\Notifications\InvoiceSentNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }

$tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
$staffUser = User::withoutGlobalScopes()->where('tenant_id', $tenant->id)->firstOrFail();

/** @var array $calls populated by the active fake; each entry: ['type' => media|message|mosms, ...] */
$calls = [];

function fakeExternal(array &$calls, array $opts = []): void {
    Http::swap(new \Illuminate\Http\Client\Factory());
    Http::preventStrayRequests();
    $failMedia = $opts['failMedia'] ?? false;
    $failMessage = $opts['failMessage'] ?? false;

    Http::fake(function ($request) use (&$calls, $failMedia, $failMessage) {
        $url = $request->url();

        if (str_contains($url, 'graph.facebook.com')) {
            if (str_contains($url, '/media')) {
                $calls[] = ['type' => 'media', 'url' => $url];
                if ($failMedia) {
                    return Http::response(['error' => ['message' => 'simulated media upload failure']], 400);
                }
                return Http::response(['id' => 'fake-media-id-123'], 200);
            }
            if (str_contains($url, '/messages')) {
                $payload = $request->data();
                $calls[] = ['type' => 'message', 'url' => $url, 'payload' => $payload];
                if ($failMessage && ($payload['type'] ?? null) === 'document') {
                    return Http::response(['error' => ['message' => 'simulated message send failure']], 400);
                }
                return Http::response(['messages' => [['id' => 'wamid.fake']]], 200);
            }
        }

        if (str_contains($url, 'mosms.co.tz')) {
            $calls[] = ['type' => 'mosms', 'url' => $url, 'payload' => $request->data()];
            if (str_contains($url, '/whatsapp/templates')) {
                return Http::response(['data' => [['id' => 1, 'name' => 'custom_message', 'status' => 'approved']]], 200);
            }
            return Http::response(['status' => 'sent'], 200);
        }

        return Http::response(['ok' => true], 200);
    });
}

function scenario(string $title, callable $fn): void {
    global $fail, $tenant, $staffUser;
    echo "== $title\n";
    DB::beginTransaction();
    try {
        // The previous scenario's rollback reverts the DB row, but not this shared in-memory
        // $tenant model's attributes — refresh() so this scenario's forceFill()->save() actually
        // has something dirty to write (Eloquent silently no-ops an UPDATE with nothing dirty,
        // which would otherwise leave the DB row on whatever the FIRST scenario set it to).
        $tenant->refresh();
        auth()->login($staffUser);
        $fn();
    } catch (\Throwable $e) {
        $fail++; echo "FAIL exception: " . $e->getMessage() . ' @' . basename($e->getFile()) . ':' . $e->getLine() . "\n";
    } finally {
        DB::rollBack();
        auth()->logout();
    }
}

function dc(): DocumentController { return app(DocumentController::class); }

/** A Request whose user() resolves to the logged-in staff user — auth()->login() alone doesn't
 * wire up Request::user() when calling controller methods directly (no HTTP kernel in between). */
function req(): Request {
    global $staffUser;
    $request = Request::create('/');
    $request->setUserResolver(fn () => $staffUser);
    return $request;
}

function call(callable $f): array {
    try {
        $res = $f();
        $json = method_exists($res, 'response') ? $res->response() : $res;
        return [$json->getStatusCode(), $json->getData(true)];
    } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
        return [404, ['message' => 'Not found.']];
    }
}

function mkClient(string $name = 'PDF Client', bool $withPhone = true): Client {
    global $tenant;
    return Client::create([
        'tenant_id' => $tenant->id,
        'name' => $name . ' ' . uniqid(),
        'phone' => $withPhone ? '2557' . random_int(10000000, 99999999) : null,
        'email' => uniqid() . '@example.test',
        'status' => 'active',
    ]);
}

function mkInvoice(Client $client, float $total = 100000, string $status = 'sent'): Document {
    global $tenant;
    $doc = Document::create([
        'tenant_id' => $tenant->id, 'client_id' => $client->id, 'type' => 'invoice',
        'document_number' => 'PDFX-' . uniqid(), 'date' => now()->subDays(5)->toDateString(),
        'due_date' => now()->addDays(9)->toDateString(),
        'subtotal' => $total, 'tax_amount' => 0, 'total' => $total, 'status' => $status,
    ]);
    $doc->items()->create(['description' => 'Website Design', 'quantity' => 1, 'price' => round($total * 0.8, 2), 'discount_type' => 'percent', 'discount_value' => 0, 'tax_percent' => 0, 'tax_amount' => 0, 'total' => round($total * 0.8, 2)]);
    $doc->items()->create(['description' => 'Company Profile', 'quantity' => 1, 'price' => round($total * 0.2, 2), 'discount_type' => 'percent', 'discount_value' => 0, 'tax_percent' => 0, 'tax_amount' => 0, 'total' => round($total * 0.2, 2)]);
    return $doc;
}

$bankMethods = [
    ['value' => 'bank', 'label' => 'Bank Transfer', 'details' => [
        ['key' => 'Bank', 'value' => 'CRDB'],
        ['key' => 'Account', 'value' => '0150851484300'],
    ]],
];

// ── 1. Direct-Meta + pesapal + unpaid: PDF attached, upload-then-message, full detail companion text ──
scenario('direct-Meta + pesapal + unpaid -> PDF attached (upload then document message) + full detail text', function () use ($bankMethods) {
    global $tenant, $calls;
    $tenant->forceFill([
        'whatsapp_enabled' => true, 'whatsapp_phone_number_id' => 'PN123', 'whatsapp_access_token' => 'tok123',
        'pesapal_enabled' => true, 'payment_methods' => $bankMethods, 'currency' => 'TZS',
    ])->save();
    $calls = [];
    fakeExternal($calls);

    $client = mkClient();
    $doc = mkInvoice($client, 100000);

    [$status, $body] = call(fn () => dc()->sendWhatsApp(req(), $doc));

    ok($status === 200, "200 status (got $status): " . json_encode($body));
    ok(str_contains($body['message'] ?? '', 'PDF attached'), 'success message says PDF attached');
    ok(count($calls) === 3, 'exactly 3 external calls (upload, document message, text message), got ' . count($calls));
    ok(($calls[0]['type'] ?? null) === 'media', 'call 1 is the media upload');
    ok(($calls[1]['type'] ?? null) === 'message' && ($calls[1]['payload']['type'] ?? null) === 'document', 'call 2 is the document message');
    ok(($calls[1]['payload']['document']['id'] ?? null) === 'fake-media-id-123', 'document message references the uploaded media id');
    ok(($calls[1]['payload']['document']['filename'] ?? null) === "{$doc->document_number}.pdf", 'document filename matches document_number');
    ok(($calls[2]['type'] ?? null) === 'message' && ($calls[2]['payload']['type'] ?? null) === 'text', 'call 3 is the companion text message');

    $text = $calls[2]['payload']['text']['body'] ?? '';
    ok(str_contains($text, 'Website Design'), 'detail text lists first item');
    ok(str_contains($text, 'Company Profile'), 'detail text lists second item');
    ok(str_contains($text, 'Total: TZS'), 'detail text has a Total line');
    ok(str_contains($text, 'Balance Due: TZS'), 'detail text has a Balance Due line');
    ok(str_contains($text, 'Due Date:'), 'detail text has a Due Date line');
    ok(str_contains($text, 'Pay Online: '), 'detail text has the pay link');
    ok(str_contains($text, 'CRDB'), 'detail text also includes the configured bank details (not pay-link-only)');
    ok(!str_contains($text, 'Paid:'), 'no Paid line when nothing has been paid yet');
});

// ── 2. MoSMS-routed tenant: unchanged text-only behaviour, never a PDF ──
scenario('MoSMS-routed tenant -> unchanged text-only send, no PDF attempted', function () {
    global $tenant, $calls;
    $tenant->forceFill([
        'whatsapp_enabled' => true, 'whatsapp_phone_number_id' => null, 'whatsapp_access_token' => null,
        'pesapal_enabled' => true, 'currency' => 'TZS',
    ])->save();
    MosmsAccount::withoutGlobalScopes()->updateOrCreate(
        ['tenant_id' => $tenant->id],
        ['email' => 'mosms@test.invalid', 'token' => 'mosms-token', 'custom_template_id' => 1]
    );
    $calls = [];
    fakeExternal($calls);

    $client = mkClient();
    $doc = mkInvoice($client, 50000);

    [$status, $body] = call(fn () => dc()->sendWhatsApp(req(), $doc));

    ok($status === 200, "200 status (got $status): " . json_encode($body));
    ok(str_contains($body['message'] ?? '', 'as text'), 'success message says text fallback, not PDF attached');
    ok(!collect($calls)->contains(fn ($c) => $c['type'] === 'media'), 'no Meta media upload for a MoSMS-routed tenant');
    ok(!collect($calls)->contains(fn ($c) => $c['type'] === 'message'), 'no direct-Meta message call either — everything through MoSMS');
    ok(collect($calls)->contains(fn ($c) => $c['type'] === 'mosms'), 'the MoSMS endpoint was called instead');
});

// ── 3. Pesapal disabled: text fallback, no PDF attempt ──
scenario('direct-Meta but pesapal disabled -> text fallback, no PDF attempt', function () {
    global $tenant, $calls;
    $tenant->forceFill([
        'whatsapp_enabled' => true, 'whatsapp_phone_number_id' => 'PN123', 'whatsapp_access_token' => 'tok123',
        'pesapal_enabled' => false, 'currency' => 'TZS',
    ])->save();
    $calls = [];
    fakeExternal($calls);

    $client = mkClient();
    $doc = mkInvoice($client, 20000);

    [$status, $body] = call(fn () => dc()->sendWhatsApp(req(), $doc));

    ok($status === 200, "200 status");
    ok(str_contains($body['message'] ?? '', 'as text'), 'text fallback when pesapal disabled');
    ok(!collect($calls)->contains(fn ($c) => $c['type'] === 'media'), 'no media upload attempted');
    ok(collect($calls)->contains(fn ($c) => $c['type'] === 'message' && ($c['payload']['type'] ?? null) === 'text'), 'plain text message sent via direct Meta sendText');
});

// ── 4. Meta media upload fails -> falls back to text, document not left broken ──
scenario('Meta media upload fails -> falls back to text, document status not left broken', function () use ($bankMethods) {
    global $tenant, $calls;
    $tenant->forceFill([
        'whatsapp_enabled' => true, 'whatsapp_phone_number_id' => 'PN123', 'whatsapp_access_token' => 'tok123',
        'pesapal_enabled' => true, 'payment_methods' => $bankMethods, 'currency' => 'TZS',
    ])->save();
    $calls = [];
    fakeExternal($calls, ['failMedia' => true]);

    $client = mkClient();
    $doc = mkInvoice($client, 70000, 'draft');

    [$status, $body] = call(fn () => dc()->sendWhatsApp(req(), $doc));

    ok($status === 200, "200 status despite Meta failure (fell back to text), got $status: " . json_encode($body));
    ok(str_contains($body['message'] ?? '', 'as text'), 'falls back to text on Meta upload failure');
    ok($doc->fresh()->status === 'sent', 'document status still advanced to sent — not left broken by the fallback');
    ok(collect($calls)->contains(fn ($c) => $c['type'] === 'media'), 'media upload was attempted');
    ok(!collect($calls)->contains(fn ($c) => $c['type'] === 'message' && ($c['payload']['type'] ?? null) === 'document'), 'no document message sent since the upload failed');
});

// ── 5. Meta document-message send fails after a successful upload -> falls back to text ──
scenario('Meta document-message send fails after upload succeeds -> falls back to text', function () use ($bankMethods) {
    global $tenant, $calls;
    $tenant->forceFill([
        'whatsapp_enabled' => true, 'whatsapp_phone_number_id' => 'PN123', 'whatsapp_access_token' => 'tok123',
        'pesapal_enabled' => true, 'payment_methods' => $bankMethods, 'currency' => 'TZS',
    ])->save();
    $calls = [];
    fakeExternal($calls, ['failMessage' => true]);

    $client = mkClient();
    $doc = mkInvoice($client, 30000, 'sent');

    [$status, $body] = call(fn () => dc()->sendWhatsApp(req(), $doc));

    ok($status === 200, "200 status, got $status");
    ok(str_contains($body['message'] ?? '', 'as text'), 'falls back to text when the document message post fails');
    ok(collect($calls)->contains(fn ($c) => $c['type'] === 'media'), 'upload happened before the failure');
    ok(collect($calls)->filter(fn ($c) => $c['type'] === 'message' && ($c['payload']['type'] ?? null) === 'text')->isNotEmpty(), 'text fallback message was eventually sent');
});

// ── 6. Fallback text (InvoiceSentNotification::toWhatsApp) now shows BOTH the pay link AND payment methods ──
scenario('fallback text includes both the pay link and configured payment methods (bug fix)', function () use ($bankMethods) {
    global $tenant;
    $tenant->forceFill([
        'whatsapp_enabled' => true, 'whatsapp_phone_number_id' => null, 'whatsapp_access_token' => null,
        'pesapal_enabled' => true, 'payment_methods' => $bankMethods, 'currency' => 'TZS',
    ])->save();
    // Not linked to MoSMS and no direct-Meta creds -> WhatsAppChannel::send() will fail to actually
    // deliver, but toWhatsApp() itself (what we're asserting on) doesn't care about the transport.
    $client = mkClient();
    $doc = mkInvoice($client, 40000);
    $doc->load('client', 'tenant');

    $text = (new InvoiceSentNotification($doc))->toWhatsApp($client);

    ok(str_contains($text, 'Bonyeza kulipa: '), 'includes the pay-online link');
    ok(str_contains($text, 'CRDB'), 'also includes the configured bank details, not pay-link-only');
});

// ── 7. Cancelled / disabled / no-phone refusals: unchanged ──
scenario('cancelled document refused, unchanged', function () {
    global $tenant;
    $tenant->forceFill(['whatsapp_enabled' => true])->save();
    $doc = mkInvoice(mkClient(), 10000, 'cancelled');
    [$status, $body] = call(fn () => dc()->sendWhatsApp(req(), $doc));
    ok($status === 422, "422 for cancelled, got $status");
    ok(str_contains($body['message'] ?? '', 'cancelled'), 'refusal message mentions cancelled');
});

scenario('WhatsApp disabled refused, unchanged', function () {
    global $tenant;
    $tenant->forceFill(['whatsapp_enabled' => false])->save();
    $doc = mkInvoice(mkClient(), 10000, 'sent');
    [$status, ] = call(fn () => dc()->sendWhatsApp(req(), $doc));
    ok($status === 422, "422 when WhatsApp disabled, got $status");
});

scenario('no client phone refused, unchanged', function () {
    global $tenant;
    $tenant->forceFill(['whatsapp_enabled' => true])->save();
    $doc = mkInvoice(mkClient('No Phone', false), 10000, 'sent');
    [$status, ] = call(fn () => dc()->sendWhatsApp(req(), $doc));
    ok($status === 422, "422 when no phone, got $status");
});

// ── 8. Tenant isolation ──
scenario("tenant isolation: another tenant's document is invisible under our scope", function () {
    global $staffUser;

    // Log out first: BelongsToTenant::creating() forces tenant_id = the logged-in user's tenant,
    // so a genuinely different tenant's row has to be created while logged in as ITS OWN user.
    auth()->logout();
    $otherTenant = Tenant::create(['name' => 'WA PDF Isolation Tenant ' . uniqid(), 'email' => uniqid() . '@example.test', 'is_active' => true]);
    $otherUser = User::withoutGlobalScopes()->create(['tenant_id' => $otherTenant->id, 'name' => 'Other Admin', 'email' => uniqid() . '@example.test', 'password' => 'x', 'role' => 'user', 'is_active' => true]);
    auth()->login($otherUser);
    $otherClient = Client::create(['tenant_id' => $otherTenant->id, 'name' => 'Other Client', 'phone' => '255700000000', 'email' => uniqid() . '@example.test', 'status' => 'active']);
    $otherDoc = Document::create([
        'tenant_id' => $otherTenant->id, 'client_id' => $otherClient->id, 'type' => 'invoice',
        'document_number' => 'OTH-' . uniqid(), 'date' => now()->toDateString(), 'due_date' => now()->addDays(7)->toDateString(),
        'subtotal' => 1000, 'tax_amount' => 0, 'total' => 1000, 'status' => 'sent',
    ]);

    auth()->login($staffUser);
    $caught = false;
    try {
        Document::findOrFail($otherDoc->id);
    } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
        $caught = true;
    }
    ok($caught, "another tenant's document is invisible under our tenant scope");
});

echo "\n" . ($fail === 0 ? 'ALL PASSED' : "$fail FAILURES") . "\n";
exit($fail === 0 ? 0 : 1);
